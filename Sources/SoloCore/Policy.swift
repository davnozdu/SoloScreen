import Foundation

/// Ручное переопределение автоматики, выставляемое горячей клавишей или меню.
public enum ManualOverride: Equatable, Sendable {
    /// Автоматика решает сама.
    case none
    /// Пользователь принудительно вернул встроенный экран, не отключая очки.
    case forceBuiltinOn
    /// Пользователь принудительно погасил встроенный экран ради конкретного
    /// внешнего. Экран запоминается, чтобы отключение именно его снимало
    /// переопределение: иначе выключенный встроенный так и остался бы
    /// выключенным.
    case forceBuiltinOff(anchor: DisplayIdentity?)

    public var isForcedOff: Bool {
        if case .forceBuiltinOff = self { return true }
        return false
    }
}

/// Что сделать со встроенным экраном.
public enum BuiltinAction: String, Sendable, Equatable {
    case enable
    case disable
    case leaveAsIs
}

public struct PolicyInput: Sendable {
    /// Все подключённые экраны, включая встроенный.
    public let displays: [DisplaySnapshot]
    /// Включён ли сейчас встроенный экран.
    public let builtinEnabled: Bool
    /// Белый список: для этих устройств встроенный экран гасится.
    public let trusted: Set<DisplayIdentity>
    public let override: ManualOverride
    /// Устройства, для которых автоматика временно не работает.
    ///
    /// Так помечаются экраны, пережившие сон вместе с компьютером: после
    /// пробуждения панель AR-очков может не ожить, а система всё равно
    /// показывает дисплей активным. Гасить из-за этого встроенный экран нельзя —
    /// пользователь остался бы вовсе без изображения.
    public let suppressed: Set<DisplayIdentity>

    public init(displays: [DisplaySnapshot],
                builtinEnabled: Bool,
                trusted: Set<DisplayIdentity>,
                override: ManualOverride,
                suppressed: Set<DisplayIdentity> = []) {
        self.displays = displays
        self.builtinEnabled = builtinEnabled
        self.trusted = trusted
        self.override = override
        self.suppressed = suppressed
    }

    /// Заглушки системы внешними экранами не считаются.
    public var externals: [DisplaySnapshot] {
        displays.filter { !$0.isBuiltin && !$0.identity.isPlaceholder }
    }
    public var hasAnyExternal: Bool { !externals.isEmpty }
    public var hasTrustedExternal: Bool {
        externals.contains { trusted.contains($0.identity) && !suppressed.contains($0.identity) }
    }
}

public struct PolicyDecision: Sendable, Equatable {
    public let action: BuiltinAction
    /// Оверрайд после применения решения: автоматика сбрасывает его, когда он
    /// перестаёт иметь смысл.
    public let override: ManualOverride

    public init(action: BuiltinAction, override: ManualOverride) {
        self.action = action
        self.override = override
    }
}

public enum Policy {
    /// Решает судьбу встроенного экрана.
    ///
    /// Главное правило — безопасность: остаться без единого экрана нельзя ни при
    /// каком сочетании оверрайда и белого списка, поэтому проверка на отсутствие
    /// внешних экранов стоит первой и перекрывает всё остальное.
    public static func decide(_ input: PolicyInput) -> PolicyDecision {
        // Рубеж 1: нет ни одного внешнего экрана — встроенный обязан работать,
        // а ручной оверрайд теряет смысл и сбрасывается.
        guard input.hasAnyExternal else {
            return PolicyDecision(action: input.builtinEnabled ? .leaveAsIs : .enable,
                                  override: .none)
        }

        switch input.override {
        case .forceBuiltinOn:
            return PolicyDecision(action: input.builtinEnabled ? .leaveAsIs : .enable,
                                  override: .forceBuiltinOn)
        case .forceBuiltinOff(let anchor):
            // Экран, ради которого гасили встроенный, отключили — держать
            // встроенный выключенным больше не за чем.
            if let anchor, !input.externals.contains(where: { $0.identity == anchor }) {
                return PolicyDecision(action: input.builtinEnabled ? .leaveAsIs : .enable,
                                      override: .none)
            }
            return PolicyDecision(action: input.builtinEnabled ? .disable : .leaveAsIs,
                                  override: .forceBuiltinOff(anchor: anchor))
        case .none:
            let shouldDisable = input.hasTrustedExternal
            if shouldDisable {
                return PolicyDecision(action: input.builtinEnabled ? .disable : .leaveAsIs,
                                      override: .none)
            }
            return PolicyDecision(action: input.builtinEnabled ? .leaveAsIs : .enable,
                                  override: .none)
        }
    }

    /// Оверрайд для явного переключения тумблером в настройках или меню.
    ///
    /// Как и у горячей клавиши, погасить встроенный экран можно только когда
    /// есть внешний.
    public static func override(settingBuiltinEnabled enabled: Bool,
                                _ input: PolicyInput) -> ManualOverride {
        guard input.hasAnyExternal else { return .none }
        return enabled ? .forceBuiltinOn : .forceBuiltinOff(anchor: input.externals.first?.identity)
    }

    /// Новый оверрайд после нажатия горячей клавиши.
    ///
    /// Гасить встроенный экран разрешено только когда есть внешний: иначе
    /// нажатие оставило бы систему вообще без изображения.
    public static func toggle(_ input: PolicyInput) -> ManualOverride {
        guard input.hasAnyExternal else { return .none }
        return input.builtinEnabled
            ? .forceBuiltinOff(anchor: input.externals.first?.identity)
            : .forceBuiltinOn
    }
}

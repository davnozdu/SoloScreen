import AppKit
import SwiftUI
import SoloCore

/// Основное окно приложения. Вид намеренно собран из небольших карточек: так
/// важное состояние видно сразу, а редкие настройки не конкурируют с ним.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var recorder: HotKeyRecorder

    @State private var selection: Destination = .overview

    init(model: SettingsModel) {
        self.model = model
        self.recorder = model.recorder
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    pageHeader
                    pageContent
                    footer
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, idealWidth: 940, minHeight: 620, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.reload() }
    }

    // MARK: Навигация

    private enum Destination: String, CaseIterable, Identifiable {
        case overview
        case displays
        case controls

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Обзор"
            case .displays: return "Экраны"
            case .controls: return "Управление"
            }
        }

        var subtitle: String {
            switch self {
            case .overview: return "Состояние SoloScreen сейчас"
            case .displays: return "Профили и качество изображения"
            case .controls: return "Горячие клавиши и поведение приложения"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "rectangle.grid.2x2"
            case .displays: return "display.2"
            case .controls: return "slider.horizontal.3"
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.accentColor, Color.purple.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SoloScreen")
                        .font(.headline.weight(.semibold))
                    Text("Display companion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("РАЗДЕЛЫ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 10)
                    .padding(.bottom, 4)

                ForEach(Destination.allCases) { destination in
                    sidebarButton(destination)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.externals.isEmpty ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(model.externals.isEmpty ? "Ожидание устройства" : "Устройство подключено")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text("Версия (model.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(width: 220)
        .background(.regularMaterial)
    }

    private func sidebarButton(_ destination: Destination) -> some View {
        let active = selection == destination
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selection = destination }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(destination.title)
                    .font(.subheadline.weight(active ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(active ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.13) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Содержимое страниц

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selection.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(selection.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selection {
        case .overview:
            overviewPage
        case .displays:
            displaysPage
        case .controls:
            controlsPage
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusCard
            soloHeroCard
            quickStats

            sectionHeading("Подключённые устройства", detail: "Быстрый доступ к экранам")
            if model.externals.isEmpty {
                emptyDisplaysCard
            } else {
                VStack(spacing: 10) {
                    ForEach(model.externals, id: \.identity) { display in
                        displaySummary(display)
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.builtinEnabled ? Color.green.opacity(0.14) : Color.accentColor.opacity(0.14))
                Image(systemName: model.builtinEnabled ? "checkmark" : "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(model.builtinEnabled ? .green : .accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.builtinEnabled ? "Система работает штатно" : "Режим внешнего экрана активен")
                    .font(.subheadline.weight(.semibold))
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.builtinEnabled ? "Встроенный включён" : "Только внешний")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
        }
        .padding(16)
        .cardStyle()
    }

    private var soloHeroCard: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text("Режим SoloScreen")
                        .font(.title3.weight(.bold))
                }
                Text("Оставьте изображение только на внешнем экране и освободите встроенный дисплей ноутбука.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Выводить только на внешний экран", isOn: model.soloBinding)
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                    .disabled(!model.canGoSolo)

                Text(builtinHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)
            displayIllustration
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.15), Color.purple.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
        }
    }

    private var displayIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.opacity(0.72))
                .frame(width: 176, height: 132)

            Image(systemName: "laptopcomputer")
                .font(.system(size: 62, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.52))
                .offset(x: -20, y: 8)

            Image(systemName: "eyeglasses")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(13)
                .background(.background, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
                .offset(x: 34, y: -18)
        }
        .accessibilityHidden(true)
    }

    private var quickStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(icon: "display.2", color: .accentColor,
                     value: "(model.externals.count)", label: "Внешних экранов")
            statCard(icon: "keyboard", color: .purple,
                     value: model.hotKeyLabel, label: "Быстрое переключение")
            statCard(icon: "slider.horizontal.3", color: .orange,
                     value: model.externals.isEmpty ? "—" : "Готово", label: "Настройки профиля")
        }
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .cardStyle()
    }

    private func displaySummary(_ display: DisplaySnapshot) -> some View {
        Button {
            selection = .displays
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(model.currentModeLabel(for: display))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let profile = model.activeProfile(for: display) {
                    Text(profile.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private var displaysPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.externals.isEmpty {
                emptyDisplaysCard
            } else {
                Text("Изменения применяются сразу и сохраняются отдельно для каждого устройства.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    ForEach(model.externals, id: \.identity) { display in
                        displayCard(display)
                    }
                }
            }
        }
    }

    private var emptyDisplaysCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange)
            Text("Внешних экранов пока нет")
                .font(.headline)
            Text("Подключите очки или монитор — SoloScreen автоматически покажет их здесь.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .cardStyle()
    }

    private func displayCard(_ display: DisplaySnapshot) -> some View {
        let expanded = model.expansionBinding(for: display)

        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() } } label: {
                HStack(spacing: 13) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(model.activeProfile(for: display)?.name ?? "Профиль не настроен")
                            Text("·")
                            Text(model.currentModeLabel(for: display))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.quaternary, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                Divider().padding(.vertical, 18)
                deviceDetails(for: display)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .cardStyle()
    }

    @ViewBuilder
    private func deviceDetails(for display: DisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            profileSection(for: display)

            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Изображение", detail: "Разрешение и цвет")
                modeSection(for: display)
                toneSection(for: display)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Гасить встроенный экран автоматически при подключении", isOn: model.trustBinding(for: display))
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                Text("Работает только для отмеченных устройств. Обычный монитор ничего не запускает автоматически.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Профили и экран

    @ViewBuilder
    private func profileSection(for display: DisplaySnapshot) -> some View {
        let profiles = model.profiles(for: display)
        let active = model.activeProfile(for: display)

        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Профиль", detail: "Сохраняется для этого устройства")
            HStack(spacing: 8) {
                Picker("Профиль", selection: model.profileBinding(for: display)) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)

                Button { model.addProfile(for: display) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Добавить профиль на основе текущего")

                Button {
                    if let active { model.removeProfile(active.id, for: display) }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.canRemoveProfile(for: display))
                .help("Удалить профиль")
                Spacer()
            }

            if let active {
                ProfileNameField(name: active.name) { newName in
                    model.renameProfile(active.id, to: newName, for: display)
                }
                .frame(maxWidth: 360)
            }

            Text("Профили переключаются клавишей (model.profileHotKeyLabel) по кругу.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func modeSection(for display: DisplaySnapshot) -> some View {
        let resolutions = model.resolutionOptions(for: display)
        let pinned = model.isModePinned(for: display)
        let key = model.resolutionKey(for: display)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Разрешение", systemImage: "rectangle.resize")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("Разрешение", selection: model.resolutionBinding(for: display)) {
                    Text("Как решит система").tag(SettingsModel.automaticResolution)
                    ForEach(resolutions) { resolution in
                        Text(resolution.label).tag(resolution.id)
                    }
                }
                .labelsHidden()
                .frame(width: 210)

                if pinned, let size = SettingsModel.parse(key) {
                    Picker("Частота", selection: model.refreshBinding(for: display)) {
                        ForEach(model.refreshRates(for: display, width: size.width, height: size.height), id: \.self) { hz in
                            Text("(hz) Гц").tag(hz)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }
            }
            Text(modeHint(for: display, pinned: pinned))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toneSection(for display: DisplaySnapshot) -> some View {
        VStack(spacing: 13) {
            sliderRow("Яркость", icon: "sun.max", value: model.brightnessBinding(for: display), range: BrightnessLevel.minimum...BrightnessLevel.maximum,
                      valueText: "\(BrightnessLevel(model.brightnessBinding(for: display).wrappedValue).percent) %")
            sliderRow("Точка белого", icon: "circle.lefthalf.filled", value: model.whitePointBinding(for: display), range: WhitePoint.warmestKelvin...WhitePoint.neutralKelvin,
                      valueText: WhitePoint(model.whitePointBinding(for: display).wrappedValue).label)
            sliderRow("Меньше голубого", icon: "drop", value: model.blueBinding(for: display), range: 0...1,
                      valueText: "\(BlueReduction(model.blueBinding(for: display).wrappedValue).percent) %")

            Text(colorHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sliderRow(_ title: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String) -> some View {
        HStack(spacing: 11) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .frame(width: 145, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.accentColor)
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: Управление

    private var controlsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            shortcutCard
            behaviorCard
        }
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Горячие клавиши", detail: "Работают из любого приложения")
            shortcutRow(title: "Встроенный экран", subtitle: "Включить или выключить экран ноутбука", label: recorderTitle,
                        action: { model.startRecording() }, reset: { model.resetHotKey() })
            Divider()
            shortcutRow(title: "Смена профиля", subtitle: "Следующий профиль активного устройства", label: model.profileHotKeyLabel,
                        action: { model.startRecordingProfileHotKey() }, reset: { model.resetProfileHotKey() })

            if let hint = recorder.hint {
                Label(hint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func shortcutRow(title: String, subtitle: String, label: String, action: @escaping () -> Void, reset: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: action) {
                Text(label)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(recorder.isRecording)
            Button("Сбросить", action: reset)
                .buttonStyle(.bordered)
                .disabled(recorder.isRecording)
        }
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Поведение", detail: "Что делать после сна и при входе в систему")
            Toggle("После пробуждения возвращаться в режим внешнего экрана", isOn: model.restoreAfterWakeBinding)
                .toggleStyle(.switch)
                .tint(.accentColor)

            if model.restoreAfterWakeBinding.wrappedValue {
                HStack {
                    Label("Задержка восстановления", systemImage: "timer")
                    Spacer()
                    Stepper(value: model.wakeDelayBinding, in: model.wakeDelayRange) {
                        Text("(model.wakeDelayBinding.wrappedValue) с")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Text("Если очки после сна не оживут, за это время можно вернуть экран ноутбука клавишей (model.hotKeyLabel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Экран ноутбука после пробуждения остаётся включённым.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Toggle("Запускать SoloScreen при входе в систему", isOn: model.loginItemBinding)
                .toggleStyle(.switch)
                .tint(.accentColor)
        }
        .padding(18)
        .cardStyle()
    }

    // MARK: Вспомогательные элементы

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var builtinHint: String {
        if !model.canGoSolo {
            return "Подключите внешний экран, чтобы включить этот режим."
        }
        return "Также доступно по клавише (model.hotKeyLabel) и из меню в строке меню."
    }

    private var colorHint: String {
        "Точка белого делает цвет теплее, а ослабление голубого снижает синеву на экране очков."
    }

    private func modeHint(for display: DisplaySnapshot, pinned: Bool) -> String {
        let current = "Сейчас: (model.currentModeLabel(for: display))."
        guard model.hasHiDPIModes(for: display) else {
            return pinned ? "Режим закрепляется при каждом подключении." : current + " Закрепите режим, чтобы он не сбрасывался."
        }
        let hint = "Режимы «чётко» рисуют картинку вдвое плотнее и улучшают читаемость текста."
        return pinned ? hint : current + " " + hint
    }

    private var recorderTitle: String {
        if recorder.isRecording {
            return recorder.draftLabel.isEmpty ? "Нажмите…" : recorder.draftLabel
        }
        return model.hotKeyLabel
    }

    private var footer: some View {
        HStack {
            Button {
                UpdaterService.shared.checkForUpdates()
            } label: {
                Label("Проверить обновления", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canCheckUpdates)
            Spacer()
            Text("SoloScreen (model.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
    }
}

private extension View {
    func cardStyle() -> some View {
        background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

/// Имя профиля правится с задержкой: сохранять на каждое нажатие клавиши
/// нельзя — список имён разводит повторы номерами прямо во время набора.
private struct ProfileNameField: View {
    let name: String
    let commit: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Имя профиля", text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = name }
            .onChange(of: name) { _, new in if !focused { draft = new } }
            .onSubmit { commit(draft) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, draft != name { commit(draft) }
            }
    }
}

import SwiftUI
import SoloCore

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var recorder: HotKeyRecorder

    init(model: SettingsModel) {
        self.model = model
        self.recorder = model.recorder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            builtinSection
            displaysSection
            controlSection
            footer
        }
        .padding(20)
        .frame(width: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SoloScreen")
                .font(.title2.weight(.semibold))
            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Состояние встроенного экрана — главный переключатель приложения, поэтому
    /// он стоит отдельной секцией и виден всегда, а не прячется внутри карточки
    /// внешнего экрана.
    private var builtinSection: some View {
        GroupBox("Встроенный экран") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: model.soloBinding) {
                    Text("Выводить только на внешний экран")
                        .font(.body.weight(.medium))
                }
                .toggleStyle(.switch)
                .disabled(!model.canGoSolo)

                Text(builtinHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var builtinHint: String {
        if !model.canGoSolo {
            return "Недоступно: внешних экранов нет, гасить единственный экран нельзя."
        }
        return "Гасит и возвращает встроенный экран прямо сейчас. "
            + "То же делают горячая клавиша \(model.hotKeyLabel) и пункт в строке меню."
    }

    // MARK: Экраны

    private var displaysSection: some View {
        GroupBox("Подключённые экраны") {
            if model.externals.isEmpty {
                Text("Внешних экранов нет. Подключите очки, чтобы добавить их в список.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.externals.enumerated()), id: \.element.identity) { index, display in
                        if index > 0 { Divider() }
                        displayRow(display)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Карточка устройства: имя и стрелка, всё остальное — внутри. Настроек на
    /// экран стало много, и держать их развёрнутыми для каждого устройства
    /// значило бы прятать главный тумблер приложения за прокруткой.
    private func displayRow(_ display: DisplaySnapshot) -> some View {
        DisclosureGroup(isExpanded: model.expansionBinding(for: display)) {
            VStack(alignment: .leading, spacing: 12) {
                profilePicker(for: display)
                Divider()
                modePickers(for: display)
                toneSliders(for: display)
                Divider()
                Toggle("Гасить встроенный автоматически при подключении",
                       isOn: model.trustBinding(for: display))
                Text("Только для отмеченных устройств. Проектор и обычный монитор ничего не запускают.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(display.name).font(.headline)
                Spacer()
                if let profile = model.activeProfile(for: display) {
                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Профили

    @ViewBuilder
    private func profilePicker(for display: DisplaySnapshot) -> some View {
        let profiles = model.profiles(for: display)
        let active = model.activeProfile(for: display)

        HStack(spacing: 8) {
            Picker("Профиль", selection: model.profileBinding(for: display)) {
                ForEach(profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            Button {
                model.addProfile(for: display)
            } label: {
                Image(systemName: "plus")
            }
            .help("Добавить профиль на основе текущего")

            Button {
                if let active { model.removeProfile(active.id, for: display) }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(!model.canRemoveProfile(for: display))
            .help("Удалить профиль")
        }

        if let active {
            ProfileNameField(name: active.name) { newName in
                model.renameProfile(active.id, to: newName, for: display)
            }
        }

        Text(profileHint)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var profileHint: String {
        "Профили переключаются клавишей \(model.profileHotKeyLabel) по кругу "
            + "и хранятся отдельно для каждого устройства."
    }

    /// Выбор режима: у AR-очков система прячет и высокие частоты, и все режимы
    /// с удвоенной плотностью точек — а именно они делают текст читаемым.
    @ViewBuilder
    private func modePickers(for display: DisplaySnapshot) -> some View {
        let resolutions = model.resolutionOptions(for: display)
        let pinned = model.isModePinned(for: display)
        let key = model.resolutionKey(for: display)

        HStack(spacing: 8) {
            Picker("Режим", selection: model.resolutionBinding(for: display)) {
                Text("Как решит система").tag(SettingsModel.automaticResolution)
                ForEach(resolutions) { res in
                    Text(res.label).tag(res.id)
                }
            }

            if pinned, let size = SettingsModel.parse(key) {
                Picker("", selection: model.refreshBinding(for: display)) {
                    ForEach(model.refreshRates(for: display, width: size.width, height: size.height), id: \.self) { hz in
                        Text("\(hz) Гц").tag(hz)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }
        }

        Text(modeHint(for: display, pinned: pinned))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func modeHint(for display: DisplaySnapshot, pinned: Bool) -> String {
        let current = "Сейчас: \(model.currentModeLabel(for: display))."
        guard model.hasHiDPIModes(for: display) else {
            return pinned
                ? "Режим закрепляется при каждом подключении этого устройства."
                : current + " Закрепите режим, чтобы он не сбрасывался."
        }
        let hint = "Режимы «чётко» рисуют картинку вдвое плотнее и уменьшают её до размера "
            + "панели: буквы крупнее и без ступенек, рабочего стола меньше. На видео не влияют."
        return pinned ? hint : current + " " + hint
    }

    // MARK: Яркость и чёткость

    @ViewBuilder
    private func toneSliders(for display: DisplaySnapshot) -> some View {
        let brightness = model.brightnessBinding(for: display)
        let whitePoint = model.whitePointBinding(for: display)
        let blue = model.blueBinding(for: display)

        HStack {
            Text("Яркость")
            Slider(value: brightness, in: BrightnessLevel.minimum...BrightnessLevel.maximum)
            Text("\(BrightnessLevel(brightness.wrappedValue).percent) %")
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
        }

        HStack {
            Text("Точка белого")
            // Шкала перевёрнута: слева теплее, как в системных настройках.
            Slider(value: whitePoint, in: WhitePoint.warmestKelvin...WhitePoint.neutralKelvin) {
                EmptyView()
            } minimumValueLabel: {
                Text("теплее").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("нейтрально").font(.caption2).foregroundStyle(.secondary)
            }
            Text(WhitePoint(whitePoint.wrappedValue).label)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
                .foregroundStyle(.secondary)
        }

        HStack {
            Text("Меньше голубого")
            Slider(value: blue, in: 0...1)
            Text("\(BlueReduction(blue.wrappedValue).percent) %")
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
        }

        Text(colorHint)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var colorHint: String {
        "Точка белого ведёт цвет по естественной траектории нагрева, как ночной режим "
            + "системы, но только на этом экране. Ослабление голубого убирает синеву, "
            + "не трогая остального. У очков панель у самого лица, и синий бьёт в упор — "
            + "на резкость это не влияет, но глазам легче."
    }

    // MARK: Управление

    private var controlSection: some View {
        GroupBox("Управление") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Горячая клавиша")
                    Spacer()
                    Button(action: { model.startRecording() }) {
                        Text(recorderTitle)
                            .frame(minWidth: 110)
                            .monospaced()
                    }
                    .disabled(recorder.isRecording)
                    Button("Сбросить") { model.resetHotKey() }
                        .disabled(recorder.isRecording)
                }

                Text(recorder.hint ?? "Включает и выключает встроенный экран, не отключая очки.")
                    .font(.caption)
                    .foregroundStyle(recorder.hint == nil ? .secondary : .primary)

                HStack {
                    Text("Смена профиля")
                    Spacer()
                    Button(action: { model.startRecordingProfileHotKey() }) {
                        Text(model.profileHotKeyLabel)
                            .frame(minWidth: 110)
                            .monospaced()
                    }
                    .disabled(recorder.isRecording)
                    Button("Сбросить") { model.resetProfileHotKey() }
                        .disabled(recorder.isRecording)
                }

                Text("Переключает профили активного внешнего экрана по кругу.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("После пробуждения возвращаться в режим внешнего экрана",
                       isOn: model.restoreAfterWakeBinding)
                if model.restoreAfterWakeBinding.wrappedValue {
                    Stepper(value: model.wakeDelayBinding, in: model.wakeDelayRange) {
                        Text("Через \(model.wakeDelayBinding.wrappedValue) с после пробуждения")
                    }
                    Text("Если очки после сна не оживут, за это время можно успеть нажать "
                         + "\(model.hotKeyLabel) и вернуть экран ноутбука.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Экран ноутбука после пробуждения остаётся включённым. "
                         + "Чтобы вернуться к выводу только на очки, нажмите \(model.hotKeyLabel) "
                         + "или переткните кабель.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle("Запускать при входе в систему", isOn: model.loginItemBinding)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recorderTitle: String {
        if recorder.isRecording {
            return recorder.draftLabel.isEmpty ? "Нажмите…" : recorder.draftLabel
        }
        return model.hotKeyLabel
    }

    private var footer: some View {
        HStack {
            Button("Проверить обновления") { UpdaterService.shared.checkForUpdates() }
                .disabled(!model.canCheckUpdates)
            Spacer()
            Text("Версия \(model.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Имя профиля правится с задержкой: сохранять на каждое нажатие клавиши
/// нельзя — список имён разводит повторы номерами, и «Ч» превратилось бы в
/// «Ч 2» прямо во время набора.
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

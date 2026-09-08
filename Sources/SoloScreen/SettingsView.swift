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
                VStack(alignment: .leading, spacing: 14) {
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

    private func displayRow(_ display: DisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.name).font(.headline)

            Toggle("Гасить встроенный автоматически при подключении", isOn: model.trustBinding(for: display))
            Text("Только для отмеченных устройств. Проектор и обычный монитор ничего не запускают.")
                .font(.caption)
                .foregroundStyle(.secondary)

            modePickers(for: display)
        }
    }

    /// Выбор режима: macOS для AR-очков нередко берёт 60 Гц, хотя устройство
    /// умеет больше, а высокие частоты прячет из системных настроек.
    @ViewBuilder
    private func modePickers(for display: DisplaySnapshot) -> some View {
        let resolutions = model.resolutions(for: display)
        let pinned = model.isModePinned(for: display)
        let key = model.resolutionKey(for: display)

        HStack(spacing: 8) {
            Picker("Режим", selection: model.resolutionBinding(for: display)) {
                Text("Как решит система").tag(SettingsModel.automaticResolution)
                ForEach(resolutions, id: \.width) { res in
                    Text("\(res.width) × \(res.height)").tag("\(res.width)x\(res.height)")
                }
            }

            if pinned, let size = parse(key) {
                Picker("", selection: model.refreshBinding(for: display)) {
                    ForEach(model.refreshRates(for: display, width: size.0, height: size.1), id: \.self) { hz in
                        Text("\(hz) Гц").tag(hz)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }
        }

        Text(pinned
             ? "Режим закрепляется при каждом подключении этого устройства."
             : "Сейчас: \(model.currentModeLabel(for: display)). Закрепите режим, чтобы он не сбрасывался.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func parse(_ key: String) -> (Int, Int)? {
        let parts = key.split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
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

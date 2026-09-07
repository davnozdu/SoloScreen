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
        }
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

import SwiftUI
import SoloCore

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            GroupBox("Подключённые экраны") {
                if model.externals.isEmpty {
                    Text("Внешних экранов нет. Подключите очки, чтобы добавить их в список.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.externals, id: \.identity) { display in
                            Toggle(isOn: model.trustBinding(for: display)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(display.name)
                                    Text("Гасить встроенный экран при подключении")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Управление") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Горячая клавиша", selection: model.hotKeyBinding) {
                        ForEach(HotKeyChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    Text("Включает и выключает встроенный экран, не отключая очки.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Запускать при входе в систему", isOn: model.loginItemBinding)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Проверить обновления") { UpdaterService.shared.checkForUpdates() }
                    .disabled(!model.canCheckUpdates)
                Spacer()
                Text("Версия \(model.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
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
}

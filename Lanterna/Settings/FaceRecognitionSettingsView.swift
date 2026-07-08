import SwiftUI

@available(iOS 18.0, *)
struct FaceRecognitionSettingsView: View {
  @State private var names: [String] = []

  var body: some View {
    Form {
      Section(footer: Text("People remembered via voice command (\"remember this person as ...\"). Removing someone here means they'll need to be re-introduced.")) {
        if names.isEmpty {
          Text("No remembered faces yet.")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(names, id: \.self) { name in
            Text(name)
          }
          .onDelete(perform: delete)
        }
      }
    }
    .navigationTitle("Known Faces")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
  }

  private func reload() {
    names = FaceRecognitionStore.allNames()
  }

  private func delete(at offsets: IndexSet) {
    for index in offsets {
      FaceRecognitionStore.forget(name: names[index])
    }
    reload()
  }
}

import SwiftUI

@available(iOS 18.0, *)
struct FaceRecognitionSettingsView: View {
  @State private var names: [String] = []

  var body: some View {
    Form {
      Section(footer: Text("People remembered via voice command (\"remember this person as ...\"). Tap Edit, then the red minus, to remove someone.")) {
        if names.isEmpty {
          Text("No remembered faces yet.")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(names, id: \.self) { name in
            HStack(spacing: 12) {
              thumbnail(for: name)
              Text(name)
            }
          }
          .onDelete(perform: delete)
        }
      }
    }
    .navigationTitle("Known Faces")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !names.isEmpty {
        ToolbarItem(placement: .navigationBarTrailing) {
          EditButton()
        }
      }
    }
    .onAppear(perform: reload)
  }

  @ViewBuilder
  private func thumbnail(for name: String) -> some View {
    if let uiImage = FaceRecognitionStore.thumbnail(name: name) {
      Image(uiImage: uiImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    } else {
      Image(systemName: "person.crop.circle.fill")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 44, height: 44)
        .foregroundColor(.secondary.opacity(0.5))
    }
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

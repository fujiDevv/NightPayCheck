import SwiftUI
import Vision
import UIKit

struct RosterPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct RosterPhotoCropView: View {
    let photo: RosterPhoto
    let onRead: (UIImage, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var left = 0.0
    @State private var top = 0.0
    @State private var right = 1.0
    @State private var bottom = 1.0
    @State private var selecting = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NightPage {
            Text("Select your row or team. Include weekday headings when possible. Drag over the image to select an area, or adjust the edges below.")
                .font(.subheadline)
            Toggle("Drag on image to select area", isOn: $selecting)
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                Image(uiImage: photo.image)
                    .resizable().scaledToFit()
                    .overlay(alignment: .topLeading) {
                        Rectangle().stroke(.orange, lineWidth: 3)
                            .background(.orange.opacity(0.12))
                            .frame(width: width * (right - left), height: height * (bottom - top))
                            .offset(x: width * left, y: height * top)
                    }
                    .contentShape(Rectangle())
                    .gesture(selecting ? DragGesture(minimumDistance: 5).onChanged { value in
                        guard abs(value.location.x - value.startLocation.x) > 5, abs(value.location.y - value.startLocation.y) > 5 else { return }
                        left = min(1, max(0, min(value.startLocation.x, value.location.x) / width))
                        right = max(0, min(1, max(value.startLocation.x, value.location.x) / width))
                        top = min(1, max(0, min(value.startLocation.y, value.location.y) / height))
                        bottom = max(0, min(1, max(value.startLocation.y, value.location.y) / height))
                    } : nil)
            }
            .aspectRatio(photo.image.size, contentMode: .fit)
            .accessibilityLabel("Roster image with selected crop")
            NightSection("Crop edges") {
                edge("Left", value: $left, range: 0...max(0, right - 0.01))
                edge("Right", value: $right, range: min(1, left + 0.01)...1)
                edge("Top", value: $top, range: 0...max(0, bottom - 0.01))
                edge("Bottom", value: $bottom, range: min(1, top + 0.01)...1)
                Button("Select whole image") { left = 0; top = 0; right = 1; bottom = 1 }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .safeAreaInset(edge: .bottom) {
            Button(busy ? "Reading selected area…" : "Read selected area") {
                read()
            }.buttonStyle(NightPrimaryButton())
                .disabled(busy || right - left < 0.01 || bottom - top < 0.01)
                .accessibilityIdentifier("readRosterCrop")
                .padding().background(.regularMaterial)
        }
        .navigationTitle("Crop roster")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        .interactiveDismissDisabled(busy)
    }

    private func edge(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 65, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel("\(title) crop edge")
        }
    }

    private func read() {
        // Render UIImage orientation into pixels before applying the displayed crop.
        let scale = min(1, 3000 / max(photo.image.size.width, photo.image.size.height))
        let size = CGSize(width: photo.image.size.width * scale, height: photo.image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let upright = renderer.image { _ in photo.image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let full = upright.cgImage else { error = "This image could not be opened."; return }
        let rect = CGRect(x: left * Double(full.width), y: top * Double(full.height),
                          width: (right - left) * Double(full.width), height: (bottom - top) * Double(full.height)).integral
        guard let cropped = full.cropping(to: rect), let data = UIImage(cgImage: cropped).pngData() else {
            error = "Select a larger area."; return
        }
        busy = true
        error = nil
        Task {
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    try VNImageRequestHandler(data: data).perform([request])
                    let cells = (request.results ?? []).compactMap { observation -> RosterTextLayout.Cell? in
                        guard let text = observation.topCandidates(1).first?.string else { return nil }
                        return RosterTextLayout.Cell(text: text, bounds: observation.boundingBox)
                    }
                    let text = RosterTextLayout.text(from: cells)
                    guard !text.isEmpty else { throw InputError.invalid("No readable text found. Try a larger or clearer crop.") }
                    return text
                }.value
                onRead(UIImage(cgImage: cropped), text)
                dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

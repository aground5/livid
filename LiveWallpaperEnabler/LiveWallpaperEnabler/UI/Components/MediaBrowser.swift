import SwiftUI

public enum MediaBrowserViewMode: String, CaseIterable {
    case list = "List"
    case gallery = "Gallery"
    
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .gallery: return "square.grid.2x2"
        }
    }
}

struct MediaBrowser<Data, RowContent, GridContent>: View 
    where Data: RandomAccessCollection, Data.Element: Identifiable, RowContent: View, GridContent: View {
    
    var title: String
    var items: Data
    @Binding var selection: Data.Element.ID?
    @Binding var viewMode: MediaBrowserViewMode
    
    @ViewBuilder var rowContent: (Data.Element) -> RowContent
    @ViewBuilder var gridContent: (Data.Element) -> GridContent
    
    var onAdd: (() -> Void)? = nil
    
    // Default grid layout
    private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
    
    public init(
        title: String,
        items: Data,
        selection: Binding<Data.Element.ID?>,
        viewMode: Binding<MediaBrowserViewMode>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent,
        @ViewBuilder gridContent: @escaping (Data.Element) -> GridContent,
        onAdd: (() -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self._selection = selection
        self._viewMode = viewMode
        self.rowContent = rowContent
        self.gridContent = gridContent
        self.onAdd = onAdd
    }
    
    var body: some View {
        ZStack {
            if viewMode == .list {
                List(selection: $selection) {
                    ForEach(items) { item in
                        rowContent(item)
                            .tag(item.id)
                    }
                }
                .listStyle(.sidebar)
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(items) { item in
                            gridContent(item)
                                .frame(maxWidth: .infinity)
                                .onTapGesture {
                                    selection = item.id
                                }
                                .modifier(GridSelectionModifier(isSelected: selection == item.id))
                        }
                    }
                    .padding(24)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Picker("View Mode", selection: $viewMode) {
                    ForEach(MediaBrowserViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
                .pickerStyle(.inline)
                
                if let onAdd {
                    Button(action: onAdd) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        }
    }
}

private struct GridSelectionModifier: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle()) // ensure tap area is good
    }
}

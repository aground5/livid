import SwiftUI

struct MainView: View {
    @State private var viewModel = MainViewModel()
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $viewModel.selectedTab)
        } detail: {
            ZStack {
                // 1. Background layer that ignores safe area
                (viewModel.selectedTab == .edit && viewModel.selectedVideoURL != nil ? Color.black : Color.clear)
                    .ignoresSafeArea()
                
                // 2. Content layer that respects safe area
                Group {
                    switch viewModel.selectedTab {
                    case .prepare:
                        prepareContentView
                    case .edit:
                        editContentView
                    case .render:
                        renderContentView
                    case .library:
                        libraryContentView
                    case .catalog:
                        catalogContentView
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    // MARK: - Content Views
    
    private var prepareContentView: some View {
        PrepareView(viewModel: viewModel)
    }
    
    private var editContentView: some View {
        EditorView(viewModel: viewModel)
    }
    
    private var renderContentView: some View {
        RenderView(viewModel: viewModel)
    }
    
    private var libraryContentView: some View {
        LibraryView(viewModel: viewModel)
    }
    
    private var catalogContentView: some View {
        CatalogView(viewModel: viewModel)
    }
}

#Preview {
    MainView()
}

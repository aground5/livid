import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: AppTab
    
    var body: some View {
        List(selection: Binding(
            get: { selectedTab },
            set: { if let newValue = $0 { selectedTab = newValue } }
        )) {
            Section("Create") {
                NavigationLink(value: AppTab.prepare) {
                    Label("Start", systemImage: "plus.circle")
                }
                
                NavigationLink(value: AppTab.edit) {
                    Label("Editor", systemImage: "scissors")
                }
            }
            
            Section("Process") {
                NavigationLink(value: AppTab.render) {
                    Label("Export", systemImage: "cpu")
                }
            }
            
            Section("Library") {
                NavigationLink(value: AppTab.library) {
                    Label("My Collection", systemImage: "photo.stack")
                }
                
                NavigationLink(value: AppTab.catalog) {
                    Label("Aerial Catalog", systemImage: "globe.americas.fill")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

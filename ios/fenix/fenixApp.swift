//
//  fenixApp.swift
//  fenix
//
//  Created by Michael Fullarton on 5/6/2026.
//

import SwiftUI

@main
struct fenixApp: App {
    @State private var appModel = AppModel(repository: SupabaseGymBookingRepository())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}

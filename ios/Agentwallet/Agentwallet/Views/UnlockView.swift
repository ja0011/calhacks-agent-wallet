//
//  UnlockView.swift
//  Agentwallet
//

import FamilyControls
import SwiftUI

struct UnlockView: View {
    @Environment(LockViewModel.self) private var viewModel
    @State private var isPickerPresented = false

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                Section {
                    LockStatusView(state: viewModel.state)
                }

                if !viewModel.isAuthorized {
                    Section {
                        Text("Screen Time access is needed to lock apps.")
                            .foregroundStyle(.secondary)
                        Button("Allow Screen Time Access") {
                            Task { await viewModel.requestAuthorization() }
                        }
                    }
                }

                Section("Apps to lock") {
                    Button("Choose Apps…") { isPickerPresented = true }
                        .disabled(!viewModel.isAuthorized)
                    Text(selectionSummary)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Lock Now", systemImage: "lock.fill") {
                        viewModel.lockNow()
                    }
                    .disabled(!viewModel.isAuthorized || !viewModel.hasSelection || viewModel.state == .locked)

                    Button {
                        Task { await viewModel.unlock() }
                    } label: {
                        HStack {
                            Label("Unlock", systemImage: "lock.open.fill")
                            if viewModel.isUnlocking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.state != .locked || viewModel.isUnlocking)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Unlock")
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $viewModel.selection)
            .onChange(of: viewModel.selection) {
                viewModel.selectionChanged()
            }
        }
    }

    private var selectionSummary: String {
        let apps = viewModel.selection.applicationTokens.count
        let categories = viewModel.selection.categoryTokens.count
        let sites = viewModel.selection.webDomainTokens.count
        if apps + categories + sites == 0 { return "Nothing selected" }
        return "\(apps) apps, \(categories) categories, \(sites) websites"
    }
}

/// Large lock indicator with a live countdown while temporarily unlocked.
private struct LockStatusView: View {
    let state: LockViewModel.LockState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 56))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.title2.bold())

            if case .temporarilyUnlocked(let until) = state {
                // Redraws every second; the view model handles the actual re-lock.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, until.timeIntervalSince(context.date))
                    Text("Re-locks in \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }

    private var iconName: String {
        state == .locked ? "lock.fill" : "lock.open.fill"
    }

    private var color: Color {
        switch state {
        case .locked: .red
        case .temporarilyUnlocked: .orange
        case .unlocked: .green
        }
    }

    private var title: String {
        switch state {
        case .locked: "Locked"
        case .temporarilyUnlocked: "Temporarily unlocked"
        case .unlocked: "Not locked"
        }
    }
}

#Preview {
    UnlockView()
        .environment(LockViewModel())
}

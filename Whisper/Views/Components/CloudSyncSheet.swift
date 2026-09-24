//
//  CloudSyncSheet.swift
//  Whisper
//
//  Created by Anurag Ambuj on 23/09/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct CloudSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloudSync = CloudSyncService.shared
    @ObservedObject private var googleDrive = GoogleDriveSyncService.shared
    
    @State private var isPickingFolder = false
    @State private var isAuthenticating = false
    @State private var syncNotice: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Sync Provider Section
                Section {
                    Picker("Provider", selection: $cloudSync.providerPreference) {
                        ForEach(CloudSyncService.ProviderPreference.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Active Engine")
                                    .font(.subheadline.weight(.semibold))
                                Text(activeEngineDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: cloudSync.statusIcon)
                                .foregroundColor(DS.Colors.accent)
                        }
                        
                        Spacer()
                        
                        Text(cloudSync.activeProvider.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundColor(.accentColor)
                    }
                } header: {
                    Text("Sync Provider")
                } footer: {
                    Text(providerFooterNote)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Google Drive Direct Connection
                if cloudSync.activeProvider == .googleDrive || cloudSync.providerPreference == .googleDrive {
                    Section("Google Drive Account") {
                        if googleDrive.isDirectAPIConnected {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connected to Google Drive")
                                        .font(.subheadline.weight(.medium))
                                    if let email = googleDrive.directUserEmail {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Disconnect", role: .destructive) {
                                    googleDrive.signOutDirectAccount()
                                    syncNotice = "Disconnected from Google Drive."
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                if let error = googleDrive.lastErrorMessage {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text("Permission Action Required")
                                                .font(.caption.bold())
                                                .foregroundColor(.primary)
                                        }
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                } else {
                                    Text("Sign in to automatically sync your books, reading progress, and bookmarks with Google Drive.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button(action: handleDirectGoogleSignIn) {
                                    HStack(spacing: 10) {
                                        if isAuthenticating {
                                            ProgressView()
                                                .tint(.white)
                                                .controlSize(.small)
                                            Text("Signing in with Google...")
                                                .font(.body.weight(.semibold))
                                                .foregroundColor(.white)
                                        } else {
                                            Image(systemName: "person.badge.key.fill")
                                                .font(.body.weight(.semibold))
                                                .foregroundColor(.white)
                                            Text("Sign in with Google")
                                                .font(.body.weight(.semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color(red: 0.26, green: 0.52, blue: 0.96)) // Google Blue #4285F4
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isAuthenticating)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // MARK: - Alternative: Linked Files App Folder
                    Section("Alternative: Linked Files App Folder") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "folder.fill.badge.gearshape")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Linked Cloud Folder")
                                        .font(.subheadline.weight(.medium))
                                    if let folderName = googleDrive.linkedFolderName {
                                        Text("Folder: \(folderName)")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Prefer zero sign-in? Link any folder from Google Drive or Files app.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: { isPickingFolder = true }) {
                                    Label(
                                        googleDrive.isLinkedFolderActive ? "Change Folder" : "Link Folder...",
                                        systemImage: "folder.badge.plus"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                if googleDrive.isLinkedFolderActive {
                                    Button(role: .destructive, action: {
                                        googleDrive.unlinkFolder()
                                    }) {
                                        Text("Unlink")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // MARK: - iCloud Status Section
                if cloudSync.activeProvider == .iCloud || cloudSync.providerPreference == .iCloud {
                    Section("iCloud Status") {
                        HStack {
                            Text("Account Status")
                            Spacer()
                            Text(cloudSync.status.localizedDescription)
                                .foregroundColor(.secondary)
                        }
                        
                        if !EntitlementHelper.isEntitledForiCloud {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Developer Membership Required", systemImage: "info.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.orange)
                                Text("Native cross-device iCloud synchronization requires a paid Apple Developer Program membership. On Personal / Free accounts, select 'Auto' or 'Google Drive' to sync for free.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // MARK: - Manual Sync Section
                Section {
                    Button(action: {
                        Task {
                            await cloudSync.triggerSync()
                            syncNotice = "Sync completed successfully."
                        }
                    }) {
                        HStack(spacing: 8) {
                            if cloudSync.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text(googleDrive.syncStatusMessage ?? "Syncing...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                        .foregroundColor(cloudSync.activeProvider == .disabled ? .secondary : .accentColor)
                    }
                    .disabled(cloudSync.isSyncing || cloudSync.activeProvider == .disabled)
                    
                    if let lastDate = cloudSync.lastSyncDate {
                        HStack {
                            Text("Last Synced")
                            Spacer()
                            Text(lastDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                    
                    if let error = googleDrive.lastErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if let notice = syncNotice {
                        Text(notice)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Library Sync")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isPickingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        googleDrive.setLinkedFolder(url: url)
                        syncNotice = "Linked folder '\(url.lastPathComponent)'"
                        Task {
                            await cloudSync.triggerSync()
                        }
                    }
                case .failure(let error):
                    syncNotice = "Folder selection canceled: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleDirectGoogleSignIn() {
        isAuthenticating = true
        syncNotice = nil
        Task {
            do {
                try await googleDrive.signInWithGoogle()
                cloudSync.providerPreference = .googleDrive
                syncNotice = "Successfully connected to Google Drive!"
                await cloudSync.triggerSync()
            } catch {
                syncNotice = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
    
    private var activeEngineDescription: String {
        switch cloudSync.activeProvider {
        case .disabled:
            return "Library is stored locally only."
        case .iCloud:
            return "Syncing books, reading positions, and bookmarks via Apple iCloud."
        case .googleDrive:
            if googleDrive.isDirectAPIConnected {
                return "Direct REST API connection active (\(googleDrive.directUserEmail ?? ""))."
            } else if googleDrive.isLinkedFolderActive {
                return "Linked folder active: '\(googleDrive.linkedFolderName ?? "")'."
            } else {
                return "Ready to connect via direct Google sign-in or linked folder."
            }
        case .auto:
            return "Auto selection active."
        }
    }
    
    private var providerFooterNote: String {
        switch cloudSync.providerPreference {
        case .auto:
            return "Auto mode uses iCloud if entitled, and automatically falls back to Google Drive if iCloud is unavailable."
        case .iCloud:
            return "Uses Apple iCloud Drive & Key-Value storage."
        case .googleDrive:
            return "Direct Google Drive REST v3 sync and optional linked folder."
        case .disabled:
            return "Cloud synchronization is completely paused."
        }
    }
}

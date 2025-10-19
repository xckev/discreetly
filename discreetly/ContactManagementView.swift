//
//  ContactManagementView.swift
//  discreetly
//
//  Contact management interface for editing and deleting contacts
//

import SwiftUI

enum PresentationState {
    case none
    case addContact
    case deleteAlert(EmergencyContact)
}

struct ContactManagementView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var presentationState: PresentationState = .none

    var body: some View {
        NavigationView {
            VStack {
                if settingsManager.settings.contacts.isEmpty {
                    emptyStateView
                } else {
                    contactListView
                }
            }
            .navigationTitle("Emergency Contacts")
            .navigationBarItems(
                leading: Button("Done") { dismiss() },
                trailing: Button("Add Contact") { 
                    presentationState = .addContact 
                }
            )
            .sheet(isPresented: Binding<Bool>(
                get: { 
                    switch presentationState {
                    case .addContact:
                        return true
                    default:
                        return false
                    }
                },
                set: { _ in 
                    presentationState = .none 
                }
            )) {
                switch presentationState {
                case .addContact:
                    AddContactView { contact in
                        settingsManager.addContact(contact)
                    }
                default:
                    EmptyView()
                }
            }
            .alert("Delete Contact", isPresented: Binding<Bool>(
                get: { 
                    if case .deleteAlert = presentationState { 
                        return true 
                    } else { 
                        return false 
                    } 
                },
                set: { _ in 
                    presentationState = .none 
                }
            )) {
                Button("Cancel", role: .cancel) { 
                    presentationState = .none 
                }
                Button("Delete", role: .destructive) {
                    if case .deleteAlert(let contact) = presentationState {
                        deleteContact(contact)
                        presentationState = .none
                    }
                }
            } message: {
                if case .deleteAlert(let contact) = presentationState {
                    Text("Are you sure you want to delete '\(contact.name)'? This will remove them from all Actions and cannot be undone.")
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("No Contacts Added")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add emergency contacts to use with your Actions")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Add Emergency Contact") {
                presentationState = .addContact
            }
                        .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contactListView: some View {
        List {
            ForEach(settingsManager.settings.contacts) { contact in
                ContactRowView(
                    contact: contact,
                    onDelete: {
                        presentationState = .deleteAlert(contact)
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteContact(_ contact: EmergencyContact) {
        // Remove contact from all actions first
        for action in settingsManager.settings.actions {
            if action.contacts.contains(contact.id) {
                settingsManager.updateAction(action.id) { updatedAction in
                    updatedAction.contacts.removeAll { $0 == contact.id }
                }
            }
        }

        // Then remove the contact
        settingsManager.removeContact(id: contact.id)
    }
}

struct ContactRowView: View {
    let contact: EmergencyContact
    let onDelete: () -> Void

    @StateObject private var settingsManager = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(contact.name)
                            .font(.headline)

                        if contact.isPrimary {
                            Text("PRIMARY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }

                    Text(contact.phoneNumber)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let relationship = contact.relationship {
                        Text(relationship)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }

            HStack {
                Button("Delete") {
                    onDelete()
                }
                                .controlSize(.small)
                .foregroundColor(.red)

                Spacer()

                let actionsUsingContact = settingsManager.settings.actions.filter { $0.contacts.contains(contact.id) }
                if !actionsUsingContact.isEmpty {
                    Text("Used in \(actionsUsingContact.count) Action\(actionsUsingContact.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContactManagementView()
}

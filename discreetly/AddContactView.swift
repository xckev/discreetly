//
//  AddContactView.swift
//  discreetly
//
//  Simple contact addition view
//

import SwiftUI
import Contacts
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    @Binding var selectedContact: CNContact?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey]
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker
        
        init(_ parent: ContactPicker) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.selectedContact = contact
            picker.dismiss(animated: true)
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true)
        }
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    let onContactAdded: (EmergencyContact) -> Void

    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var relationship = ""
    @State private var isPrimary = false
    @State private var showingContactPicker = false
    @State private var selectedContact: CNContact?

    var body: some View {
        NavigationView {
            Form {
                Section("Emergency Contact Information") {
                    HStack {
                        TextField("Name", text: $name)
                        Button("Import", systemImage: "person.crop.circle.badge.plus") {
                            showingContactPicker = true
                        }
                        .buttonStyle(.borderless)
                    }
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Relationship (optional)", text: $relationship)
                }

                Section("Settings") {
                    Toggle("Primary Emergency Contact", isOn: $isPrimary)
                        .help("Primary emergency contacts are notified first in emergencies")
                }
            }
            .navigationTitle("Add Emergency Contact")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    saveContact()
                }
                .disabled(name.isEmpty || phoneNumber.isEmpty)
            )
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker(selectedContact: $selectedContact)
            }
            .onChange(of: selectedContact) { _, newContact in
                if let contact = newContact {
                    importContactInfo(from: contact)
                }
            }
        }
    }

    private func saveContact() {
        // Clean up phone number: remove dashes and add +1 prefix
        let cleanedPhoneNumber = formatPhoneNumber(phoneNumber)
        
        let contact = EmergencyContact(
            name: name,
            phoneNumber: cleanedPhoneNumber,
            relationship: relationship.isEmpty ? nil : relationship,
            isPrimary: isPrimary
        )
        onContactAdded(contact)
        dismiss()
    }
    
    private func formatPhoneNumber(_ number: String) -> String {
        // Remove all non-digit characters (dashes, spaces, parentheses, etc.)
        let digitsOnly = number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // If the number already starts with 1 (US country code), add +1
        // If it doesn't start with 1 and is 10 digits, assume it's a US number and add +1
        if digitsOnly.hasPrefix("1") && digitsOnly.count == 11 {
            return "+\(digitsOnly)"
        } else if digitsOnly.count == 10 {
            return "+1\(digitsOnly)"
        } else {
            // For other cases, just add +1 if it doesn't already start with +
            return number.hasPrefix("+") ? number : "+1\(digitsOnly)"
        }
    }
    
    private func importContactInfo(from contact: CNContact) {
        // Import full name
        let formatter = CNContactFormatter()
        formatter.style = .fullName
        if let fullName = formatter.string(from: contact), !fullName.isEmpty {
            name = fullName
        }
        
        // Import phone number (use the first available phone number)
        if let firstPhoneNumber = contact.phoneNumbers.first {
            phoneNumber = firstPhoneNumber.value.stringValue
        }
        
        // Clear the selected contact to allow for re-importing if needed
        selectedContact = nil
    }
}

#Preview {
    AddContactView { _ in }
}

import SwiftUI

/// Preferences window (Cmd+,): monitoring, capture, login item, and the
/// advanced detection predicate.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings()
                .environment(model)
                .tabItem { Label("Général", systemImage: "gearshape") }
            MailSettings()
                .environment(model)
                .tabItem { Label("E-mail", systemImage: "envelope") }
            IMessageSettings()
                .environment(model)
                .tabItem { Label("iMessage", systemImage: "message") }
            AdvancedSettings()
                .environment(model)
                .tabItem { Label("Avancé", systemImage: "slider.horizontal.3") }
        }
        .scenePadding()
        .frame(width: 520)
    }
}

/// Automatic e-mail-to-owner configuration (SMTP or Apple Mail).
private struct MailSettings: View {
    @Environment(AppModel.self) private var model

    @State private var password = ""
    @State private var status = ""
    @State private var sending = false
    @State private var mailAccounts: [String] = []
    @State private var loadingAccounts = false

    var body: some View {
        Form {
            Section {
                Toggle("Alerter automatiquement le propriétaire par e-mail", isOn: Binding(
                    get: { model.settings.autoNotifyOwner },
                    set: { model.settings.autoNotifyOwner = $0 }
                ))
                Picker("Méthode d'envoi", selection: Binding(
                    get: { model.settings.emailMethod },
                    set: { method in selectMethod(method) }
                )) {
                    Text("Serveur SMTP").tag(AppSettings.EmailMethod.smtp)
                    Text("Compte Apple Mail").tag(AppSettings.EmailMethod.appleMail)
                }
                Text("À chaque échec, un e-mail (avec la photo) est envoyé en arrière-plan au propriétaire — même lorsque l'écran est verrouillé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notification automatique")
            }

            if model.settings.emailMethod == .smtp {
                smtpSection
            } else {
                appleMailSection
            }

            Section {
                Button(sending ? "Envoi en cours…" : "Envoyer un e-mail de test") {
                    sendTest()
                }
                .disabled(sending)
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            password = model.settings.smtpPassword ?? ""
            if model.settings.emailMethod == .appleMail { loadAccounts() }
        }
    }

    private var smtpSection: some View {
        Section {
            TextField("Serveur SMTP (ex. smtp.gmail.com)", text: Binding(
                get: { model.settings.smtpHost },
                set: { model.settings.smtpHost = $0 }
            ))
            TextField("Port", value: Binding(
                get: { model.settings.smtpPort },
                set: { model.settings.smtpPort = $0 }
            ), format: .number.grouping(.never))
            TextField("Nom d'utilisateur", text: Binding(
                get: { model.settings.smtpUsername },
                set: { model.settings.smtpUsername = $0 }
            ))
            SecureField("Mot de passe (ou mot de passe d'application)", text: $password)
                .onChange(of: password) {
                    model.settings.smtpPassword = password.isEmpty ? nil : password
                }
            TextField("Expéditeur (optionnel, défaut = utilisateur)", text: Binding(
                get: { model.settings.smtpFrom },
                set: { model.settings.smtpFrom = $0 }
            ))
            LabeledContent("Destinataire (propriétaire)",
                           value: model.settings.ownerEmail.isEmpty ? "— à définir dans Général" : model.settings.ownerEmail)
        } header: {
            Text("Compte SMTP (TLS implicite, port 465)")
        } footer: {
            Text("Le mot de passe est conservé dans le Trousseau. Pour Gmail / iCloud, créez un « mot de passe d'application ».")
        }
    }

    private var appleMailSection: some View {
        Section {
            if mailAccounts.isEmpty {
                Text(loadingAccounts ? "Recherche des comptes…" : "Aucun compte détecté dans Mail. Cliquez sur Rafraîchir (autorisation requise).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Envoyer depuis", selection: Binding(
                    get: { model.settings.mailSenderAddress },
                    set: { model.settings.mailSenderAddress = $0 }
                )) {
                    ForEach(mailAccounts, id: \.self) { Text($0).tag($0) }
                }
            }
            Button(loadingAccounts ? "Rafraîchir…" : "Rafraîchir les comptes") { loadAccounts() }
                .disabled(loadingAccounts)
            LabeledContent("Destinataire (propriétaire)",
                           value: model.settings.ownerEmail.isEmpty ? "— à définir dans Général" : model.settings.ownerEmail)
        } header: {
            Text("Compte Apple Mail")
        } footer: {
            Text("Utilise l'app Mail avec l'un de ses comptes configurés — aucun mot de passe à saisir. Nécessite l'autorisation « Automatisation » (contrôle de Mail).")
        }
    }

    private func selectMethod(_ method: AppSettings.EmailMethod) {
        sending = true
        status = ""
        Task {
            status = await model.setEmailMethod(method)
            sending = false
            if method == .appleMail { loadAccounts() }
        }
    }

    private func loadAccounts() {
        loadingAccounts = true
        Task {
            let accounts = await model.mailSenderAddresses()
            mailAccounts = accounts
            if model.settings.mailSenderAddress.isEmpty, let first = accounts.first {
                model.settings.mailSenderAddress = first
            }
            loadingAccounts = false
        }
    }

    private func sendTest() {
        sending = true
        status = ""
        Task {
            status = await model.sendTestEmail()
            sending = false
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Surveillance") {
                Toggle("Surveiller l'écran de verrouillage", isOn: Binding(
                    get: { model.isMonitoring },
                    set: { model.setMonitoring($0) }
                ))
                Toggle("Prendre une photo à chaque échec", isOn: Binding(
                    get: { model.settings.captureOnFailure },
                    set: { model.settings.captureOnFailure = $0 }
                ))
                LabeledContent("Caméra") {
                    Text(model.cameraAuthorized ? "Autorisée" : "Non autorisée")
                        .foregroundStyle(model.cameraAuthorized ? .green : .orange)
                }
                if !model.cameraAuthorized {
                    Button(model.cameraDenied ? "Ouvrir les Réglages…" : "Autoriser la caméra…") {
                        Task { _ = await model.requestCameraAccess() }
                    }
                }
            }

            Section("Propriétaire") {
                TextField("Adresse e-mail du propriétaire", text: Binding(
                    get: { model.settings.ownerEmail },
                    set: { model.settings.ownerEmail = $0 }
                ))
                .textContentType(.emailAddress)
                Text("Utilisée par « Envoyer au propriétaire » depuis le détail d'un événement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Démarrage") {
                Toggle("Lancer Ensachage à l'ouverture de session", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section("Journal") {
                LabeledContent("Événements enregistrés", value: "\(model.history.entries.count)")
                Button("Effacer le journal et les photos", role: .destructive) {
                    model.history.clear()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Automatic iMessage-to-owner configuration (best-effort; scripts Messages).
private struct IMessageSettings: View {
    @Environment(AppModel.self) private var model

    @State private var status = ""
    @State private var sending = false

    var body: some View {
        Form {
            Section {
                Toggle("Alerter le propriétaire par iMessage", isOn: Binding(
                    get: { model.settings.autoIMessageOwner },
                    set: { newValue in
                        sending = newValue
                        status = ""
                        Task {
                            let result = await model.setIMessageEnabled(newValue)
                            status = result
                            sending = false
                        }
                    }
                ))
                .disabled(sending)
                TextField("Numéro ou identifiant iMessage (ex. +33 6…)", text: Binding(
                    get: { model.settings.ownerPhone },
                    set: { model.settings.ownerPhone = $0 }
                ))
                Text("À chaque échec, un iMessage (avec la photo) est envoyé au propriétaire via l'app Messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notification iMessage")
            } footer: {
                Text("Nécessite que Messages soit connecté à votre compte iMessage sur ce Mac, et l'autorisation « Automatisation » (contrôle de Messages). L'envoi par script est déprécié par Apple et peut ne pas fonctionner sur les versions récentes de macOS — l'e-mail reste le canal le plus fiable.")
            }

            Section {
                Button(sending ? "Envoi en cours…" : "Envoyer un iMessage de test") {
                    sendTest()
                }
                .disabled(sending)
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sendTest() {
        sending = true
        status = ""
        Task {
            status = await model.sendTestIMessage()
            sending = false
        }
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Text("Par défaut, seul un **mauvais mot de passe** déclenche une photo (jamais le verrouillage ni un déverrouillage réussi).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("La détection de l'empreinte et du code PIN (YubiKey) est expérimentale : elle peut générer de fausses photos au verrouillage tant qu'elle n'est pas ajustée pour votre Mac (utilisez `make watch-auth`).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Inclure empreinte + code PIN (expérimental)") {
                    model.settings.useExtendedPredicate()
                    rearm()
                }
            } header: {
                Text("Méthodes détectées")
            }

            Section {
                Text("Prédicat utilisé par `log stream`. Modifiez-le si nécessaire, puis appliquez.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { model.settings.failurePredicate },
                    set: { model.settings.failurePredicate = $0 }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                HStack {
                    Button("Réinitialiser (mot de passe seul)") { model.settings.resetPredicate(); rearm() }
                    Spacer()
                    Button("Appliquer") { rearm() }
                        .keyboardShortcut(.defaultAction)
                }
            } header: {
                Text("Prédicat (avancé)")
            }
        }
        .formStyle(.grouped)
    }

    /// Re-arms the monitor so the current predicate takes effect immediately.
    private func rearm() {
        guard model.isMonitoring else { return }
        model.setMonitoring(false)
        model.setMonitoring(true)
    }
}

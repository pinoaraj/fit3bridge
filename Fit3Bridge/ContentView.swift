import SwiftUI

struct ContentView: View {
    @StateObject private var fit3 = Fit3Manager.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var showLogs = false
    @State private var showHealthKitAlert = false
    @State private var healthKitAlertMessage = ""
    @State private var lastSyncResult: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                headerSection
                metricsGrid
                actionButtons
                if showLogs {
                    logsSection
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            healthKit.requestAuthorization()
        }
        .alert("Apple Salud", isPresented: $showHealthKitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthKitAlertMessage)
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fit3Bridge")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(fit3.connectionState)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(connectionColor)
            }
            Spacer()
            Circle()
                .fill(connectionColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: connectionColor.opacity(0.6), radius: 4)
        }
    }

    private var connectionColor: Color {
        switch fit3.connectionState {
        case "Conectado", "Conectado - Descubriendo servicios": return .green
        case "Conectando...": return .orange
        case "Escaneando...": return .blue
        default: return .red
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                title: "PASOS",
                value: "\(fit3.steps.formatted())",
                unit: "",
                icon: "figure.walk",
                color: .blue
            )
            MetricCard(
                title: "DISTANCIA",
                value: String(format: "%.2f", fit3.distanceMeters / 1000),
                unit: "km",
                icon: "location.north.line",
                color: .green
            )
            MetricCard(
                title: "CALORÍAS",
                value: "\(fit3.calories.formatted())",
                unit: "kcal",
                icon: "flame.fill",
                color: .orange
            )
            MetricCard(
                title: "PULSO",
                value: fit3.heartRate > 0 ? "\(fit3.heartRate)" : "—",
                unit: "BPM",
                icon: "heart.fill",
                color: .red
            )
            MetricCard(
                title: "BATERÍA",
                value: "\(fit3.batteryLevel)",
                unit: "%",
                icon: batteryIcon,
                color: batteryColor
            )
            MetricCard(
                title: "ESTADO",
                value: fit3.isConnected ? "Conectado" : "Desconectado",
                unit: "",
                icon: fit3.isConnected ? "link" : "link.badge.plus",
                color: fit3.isConnected ? .green : .gray
            )
        }
    }

    private var batteryIcon: String {
        switch fit3.batteryLevel {
        case 0..<20: return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<75: return "battery.50"
        case 75..<95: return "battery.75"
        default: return "battery.100"
        }
    }

    private var batteryColor: Color {
        switch fit3.batteryLevel {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .green
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                if fit3.isConnected {
                    fit3.disconnect()
                } else {
                    fit3.startScan()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: fit3.isConnected ? "xmark.circle.fill" : "magnifyingglass")
                    Text(fit3.isConnected ? "Desconectar" : (fit3.isScanning ? "Escaneando..." : "Conectar Fit3"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fit3.isConnected ? Color.red.opacity(0.85) : Color.blue.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(fit3.isScanning && !fit3.isConnected)

            Button(action: syncToHealthKit) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                    Text("Guardar en Apple Salud")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.pink.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!fit3.isConnected || fit3.steps == 0)

            Button(action: { showLogs.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: showLogs ? "chevron.up" : "chevron.down")
                    Text("Logs BLE")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logs BLE (Hex)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Limpiar") { fit3.bleLogs.removeAll() }
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(fit3.bleLogs, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: 180)
            .padding(10)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func syncToHealthKit() {
        Task {
            let success = await healthKit.syncTodayData(steps: fit3.steps, distanceMeters: fit3.distanceMeters)
            await MainActor.run {
                healthKitAlertMessage = success
                    ? "✅ Sincronizado: \(fit3.steps.formatted()) pasos, \(String(format: "%.2f", fit3.distanceMeters/1000)) km"
                    : "❌ Error: \(healthKit.authorizationError ?? "Desconocido")"
                showHealthKitAlert = true
                if success { lastSyncResult = healthKitAlertMessage }
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
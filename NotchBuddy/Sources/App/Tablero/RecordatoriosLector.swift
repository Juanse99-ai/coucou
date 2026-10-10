import Foundation
import EventKit

// MARK: - Tablero: Recordatorios de Apple
//
// Lee los recordatorios sin terminar y marca como hecho el que se toca en el
// tablero. Todo pasa en el Mac (EventKit): lo que se agrega en el iPhone o con
// Siri llega por iCloud a la app Recordatorios y de ahi al tablero.
// EventKit responde en otro hilo, por eso esta clase no es @MainActor y solo
// devuelve datos Sendable; PendientesStore los lleva a la vista.

/// Lo que el tablero necesita de un recordatorio.
struct RecordatorioDato: Sendable {
    let id: String
    let titulo: String
    let vence: Date?
    let lista: String
}

final class RecordatoriosLector: @unchecked Sendable {
    static let shared = RecordatoriosLector()
    private let store = EKEventStore()

    private init() {}

    /// Hay permiso completo para leer y marcar recordatorios.
    static var conAcceso: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    /// Muestra el aviso de macOS la primera vez. true si dio permiso.
    func pedirAcceso() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Los recordatorios sin terminar de todas las listas.
    func pendientes() async -> [RecordatorioDato] {
        let predicado = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuacion in
            _ = store.fetchReminders(matching: predicado) { recordatorios in
                let datos = (recordatorios ?? []).map { r in
                    RecordatorioDato(id: r.calendarItemIdentifier,
                                     titulo: r.title ?? "",
                                     vence: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                                     lista: (r.calendar as EKCalendar?)?.title ?? "")
                }
                continuacion.resume(returning: datos)
            }
        }
    }

    /// Marca el recordatorio como hecho en la app Recordatorios. false si no se pudo.
    func completar(_ id: String) -> Bool {
        guard let recordatorio = store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        recordatorio.isCompleted = true
        do {
            try store.save(recordatorio, commit: true)
            return true
        } catch {
            return false
        }
    }
}

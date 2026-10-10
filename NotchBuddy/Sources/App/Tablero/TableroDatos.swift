import Foundation

// MARK: - Tablero: datos
//
// Lo que pinta cada tarjeta del tablero (TableroView). Las fuentes reales
// (TableroFuentes: el MacBook, Vercel y GitHub) llenan estas mismas
// estructuras; TableroMuestra queda para lo que aun no tiene fuente
// (Novedades) y para el primer instante antes de medir.

/// Estado de un vigilante o de un servicio: el color del punto.
enum TableroEstado: String, Codable, Sendable {
    case bien, aviso, falla, apagado

    var colorHex: String {
        switch self {
        case .bien:    return "#22C55E"
        case .aviso:   return "#F59E0B"
        case .falla:   return "#F4505E"
        case .apagado: return "#6B7079"
        }
    }
}

/// Una barra de la tarjeta Consumos: cuanto va gastado de un limite.
struct TableroConsumo: Identifiable, Sendable {
    let id: String
    let nombre: String
    /// Texto a la derecha: "25%", "38 de 100", "sin clave"...
    let valor: String
    /// 0...1; nil cuando no hay barra (por ejemplo, falta la clave).
    let fraccion: Double?
    let colorHex: String
}

/// Una linea de la tarjeta Novedades.
struct TableroNovedad: Identifiable, Sendable {
    let id: String
    let texto: String
    let estado: TableroEstado
    let minutosAtras: Int
}

/// Un deploy o un push de la tarjeta Actividad.
struct TableroActividad: Identifiable, Sendable {
    enum Tipo: String, Sendable { case deploy, push }
    let id: String
    let tipo: Tipo
    let proyecto: String
    /// Deploy: "Listo", "Error"... Push: rama y mensaje del commit.
    let detalle: String
    let estado: TableroEstado
    let minutosAtras: Int
}

/// Los numeros de la tarjeta del MacBook.
struct TableroEquipo: Sendable {
    let nombre: String
    /// Carga promedio del ultimo minuto (como `uptime`).
    let carga: Double
    /// 0...1
    let memoria: Double
    /// 0...1, lo usado del disco.
    let disco: Double
    /// 0...1; nil en un Mac sin bateria.
    let bateria: Double?
    let cargando: Bool
}

/// Un repositorio de GitHub: su ultimo push y como va el CI de la rama principal.
struct TableroRepo: Identifiable, Sendable {
    enum CI: Sendable {
        case verde, falla, corriendo, sinCI

        init(rawGitHub: String?) {
            switch (rawGitHub ?? "").uppercased() {
            case "SUCCESS":             self = .verde
            case "FAILURE", "ERROR":    self = .falla
            case "PENDING", "EXPECTED": self = .corriendo
            default:                    self = .sinCI
            }
        }

        var estado: TableroEstado {
            switch self {
            case .verde:     return .bien
            case .falla:     return .falla
            case .corriendo: return .aviso
            case .sinCI:     return .apagado
            }
        }

        var texto: String {
            switch self {
            case .verde:     return "CI en verde"
            case .falla:     return "CI con fallas"
            case .corriendo: return "CI corriendo"
            case .sinCI:     return "sin CI"
            }
        }
    }

    /// "owner/repo"
    let id: String
    let nombre: String
    let rama: String
    let push: Date
    let ci: CI
}

/// Un vigilante de la barra de abajo: algo que el panel revisa solo.
struct TableroVigilante: Identifiable, Sendable {
    let id: String
    let nombre: String
    let estado: TableroEstado
}

// MARK: - Tiempos

enum TableroTiempo {
    /// "ahora", "hace 12 min", "hace 3 h", "ayer", "hace 4 d".
    static func hace(_ minutos: Int) -> String {
        if minutos < 1 { return "ahora" }
        if minutos < 60 { return "hace \(minutos) min" }
        let horas = minutos / 60
        if horas < 24 { return "hace \(horas) h" }
        let dias = horas / 24
        return dias == 1 ? "ayer" : "hace \(dias) d"
    }

    /// Version corta para las tarjetas angostas: "ahora", "12 min", "3 h", "ayer", "4 d".
    static func corto(_ minutos: Int) -> String {
        if minutos < 1 { return "ahora" }
        if minutos < 60 { return "\(minutos) min" }
        let horas = minutos / 60
        if horas < 24 { return "\(horas) h" }
        let dias = horas / 24
        return dias == 1 ? "ayer" : "\(dias) d"
    }

    /// Porcentaje entero: 0.62 -> "62%".
    static func porcentaje(_ fraccion: Double) -> String {
        "\(Int((min(max(fraccion, 0), 1) * 100).rounded()))%"
    }

    /// Minutos enteros entre una fecha y ahora (0 si es del futuro).
    static func minutos(desde fecha: Date, ahora: Date = Date()) -> Int {
        max(0, Int(ahora.timeIntervalSince(fecha) / 60))
    }
}

// MARK: - Datos de muestra

enum TableroMuestra {
    static let consumos: [TableroConsumo] = [
        TableroConsumo(id: "claude-sesion", nombre: "Claude sesión", valor: "12%", fraccion: 0.12, colorHex: "#22C55E"),
        TableroConsumo(id: "claude-semana", nombre: "Claude semana", valor: "25%", fraccion: 0.25, colorHex: "#22C55E"),
        TableroConsumo(id: "vercel", nombre: "Vercel", valor: "38 deploys · 6 d", fraccion: 0.38, colorHex: "#A78BFA"),
        TableroConsumo(id: "github", nombre: "GitHub", valor: "420 de 2.000 min", fraccion: 0.21, colorHex: "#38BDF8"),
    ]

    static let novedades: [TableroNovedad] = [
        TableroNovedad(id: "n1", texto: "Cargador conectado", estado: .bien, minutosAtras: 0),
        TableroNovedad(id: "n2", texto: "Deploy listo: mi-app", estado: .bien, minutosAtras: 12),
        TableroNovedad(id: "n3", texto: "Push nuevo en main", estado: .bien, minutosAtras: 58),
        TableroNovedad(id: "n4", texto: "Wi-Fi desconectado", estado: .falla, minutosAtras: 135),
    ]

    static let pendientes: [Pendiente] = [
        Pendiente(id: "p1", titulo: "Renovar el dominio", detalle: "Vence el viernes"),
        Pendiente(id: "p2", titulo: "Pagar la tarjeta", detalle: "Antes del 15"),
        Pendiente(id: "p3", titulo: "Llamar al proveedor", detalle: "Cotización del seguro"),
        Pendiente(id: "p4", titulo: "Respaldar el MacBook", detalle: "Time Machine"),
    ]

    static let actividad: [TableroActividad] = [
        TableroActividad(id: "a1", tipo: .deploy, proyecto: "mi-app", detalle: "Listo", estado: .bien, minutosAtras: 12),
        TableroActividad(id: "a2", tipo: .deploy, proyecto: "mi-sitio", detalle: "Listo", estado: .bien, minutosAtras: 190),
        TableroActividad(id: "a3", tipo: .push, proyecto: "mi-app", detalle: "main · arregla el menú", estado: .bien, minutosAtras: 58),
        TableroActividad(id: "a4", tipo: .push, proyecto: "panel", detalle: "main · tarjeta del MacBook", estado: .aviso, minutosAtras: 420),
    ]

    static let equipo = TableroEquipo(nombre: "MacBook", carga: 1.84, memoria: 0.62, disco: 0.41,
                                      bateria: 0.87, cargando: true)

    static let vigilantes: [TableroVigilante] = [
        TableroVigilante(id: "claude", nombre: "Claude", estado: .bien),
        TableroVigilante(id: "github", nombre: "GitHub", estado: .bien),
        TableroVigilante(id: "vercel", nombre: "Vercel", estado: .falla),
        TableroVigilante(id: "wifi", nombre: "Wi-Fi", estado: .bien),
        TableroVigilante(id: "bateria", nombre: "Batería", estado: .bien),
        TableroVigilante(id: "disco", nombre: "Disco", estado: .bien),
        TableroVigilante(id: "respaldo", nombre: "Respaldo", estado: .bien),
    ]
}

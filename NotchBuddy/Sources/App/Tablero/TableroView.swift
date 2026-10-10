import SwiftUI

// MARK: - Tablero
//
// La vista grande del panel (IslandView.tablero), armada como el panel de la
// foto de referencia:
//   1. Estado general (con Mochi a la izquierda) y sesiones de Claude Code.
//   2. Consumos, Novedades y Pendientes.
//   3. Deploys y pushes, y el MacBook.
//   4. Barra de vigilantes y equipos.
// Mochi lo dibuja BotPlacement en botX/botY de viewLayouts[.tablero], que cae
// en la tarjeta de estado general. Los datos salen de Coucou (AppState) y de
// TableroFuentes; lo que aun no tiene fuente (Novedades) sale de
// TableroMuestra y lleva la etiqueta "muestra".

struct TableroView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var pendientes = PendientesStore.shared
    @ObservedObject private var fuentes = TableroFuentes.shared

    private let separacion: CGFloat = 8

    /// La isla monta todas las vistas a la vez (ocultas); las fuentes solo
    /// trabajan cuando el tablero es la vista abierta.
    private var aLaVista: Bool { state.mode == .expanded && state.view == .tablero }

    private var equipo: TableroEquipo { fuentes.equipo ?? TableroMuestra.equipo }

    var body: some View {
        let vigilantes = TableroArmado.vigilantes(state: state, repos: fuentes.repos, equipo: fuentes.equipo)
        let actividad = TableroArmado.actividad(state: state, repos: fuentes.repos)
        VStack(spacing: separacion) {
            HStack(spacing: separacion) {
                TableroEstadoGeneral(vigilantes: vigilantes, revisado: fuentes.revisado)
                    .frame(width: 322)
                TableroSesiones(state: state, equipo: equipo)
            }
            .frame(height: 98)

            HStack(spacing: separacion) {
                TableroConsumos(consumos: TableroArmado.consumos(state: state, deploysHoy: fuentes.deploysHoy,
                                                                 repos: fuentes.repos))
                TableroNovedades(novedades: TableroMuestra.novedades)
                TableroPendientes(store: pendientes)
            }
            .frame(height: 150)

            HStack(spacing: separacion) {
                TableroActividadTarjeta(items: actividad.isEmpty ? TableroMuestra.actividad : actividad,
                                        muestra: actividad.isEmpty)
                TableroEquipoTarjeta(equipo: equipo, muestra: fuentes.equipo == nil)
            }
            .frame(height: 128)

            TableroBarra(vigilantes: vigilantes, equipo: equipo)
                .frame(height: 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: aLaVista) {
            guard aLaVista else { return }
            await fuentes.vigilar()
        }
    }
}

// MARK: - Colores y piezas comunes

enum TableroColor {
    static var texto: Color { Color(hex: "#F5F6F8") }
    static var suave: Color { Color(hex: "#8E939C") }
    static var tenue: Color { Color(hex: "#6B7079") }
    static var pista: Color { Color.white.opacity(0.08) }
}

/// Tarjeta del tablero: el fondo de Coucou, un titulo con su punto y el contenido.
struct TableroTarjeta<Contenido: View>: View {
    let titulo: String
    let detalle: String?
    let punto: TableroEstado?
    let muestra: Bool
    let contenido: () -> Contenido

    init(titulo: String, detalle: String? = nil, punto: TableroEstado? = nil, muestra: Bool = true,
         @ViewBuilder contenido: @escaping () -> Contenido) {
        self.titulo = titulo
        self.detalle = detalle
        self.punto = punto
        self.muestra = muestra
        self.contenido = contenido
    }

    var body: some View {
        CardBackground(wash: nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let punto = punto {
                        Circle()
                            .fill(Color(hex: punto.colorHex))
                            .frame(width: 7, height: 7)
                    }
                    Text(verbatim: titulo)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TableroColor.texto)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let detalle = detalle {
                        Text(verbatim: detalle)
                            .font(.system(size: 11))
                            .foregroundColor(TableroColor.suave)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if muestra {
                        TableroEtiquetaMuestra()
                    }
                }
                contenido()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

/// "muestra": la tarjeta todavia no tiene su fuente real conectada.
struct TableroEtiquetaMuestra: View {
    var body: some View {
        Text(verbatim: "muestra")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(TableroColor.tenue)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .fixedSize()
    }
}

/// Barra delgada de uso: pista gris y relleno de color.
struct TableroBarraUso: View {
    let fraccion: Double
    let colorHex: String
    var alto: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let f = CGFloat(min(max(fraccion, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(TableroColor.pista)
                Capsule()
                    .fill(Color(hex: colorHex))
                    .frame(width: max(alto, geo.size.width * f))
            }
        }
        .frame(height: alto)
    }
}

private func tableroDecimal(_ valor: Double) -> String {
    String(format: "%.2f", valor).replacingOccurrences(of: ".", with: ",")
}

// MARK: - 1. Estado general

/// La tarjeta grande de la izquierda: Mochi (dibujado aparte) y una frase con
/// lo primero que falla, o "Todo en orden".
struct TableroEstadoGeneral: View {
    let vigilantes: [TableroVigilante]
    let revisado: Date?

    private var conFalla: [TableroVigilante] { vigilantes.filter { $0.estado == .falla } }
    private var conAviso: [TableroVigilante] { vigilantes.filter { $0.estado == .aviso } }
    private var bien: Int { vigilantes.filter { $0.estado == .bien }.count }

    private var estado: TableroEstado {
        if !conFalla.isEmpty { return .falla }
        if !conAviso.isEmpty { return .aviso }
        return .bien
    }

    private var titulo: String {
        if let primero = conFalla.first { return primero.rotulo }
        if let primero = conAviso.first { return primero.rotulo }
        return "Todo en orden"
    }

    // Un CardBackground por color: el tinte de abajo dice como va todo.
    var body: some View {
        switch estado {
        case .falla:
            CardBackground(wash: .red) { contenido }
        case .aviso:
            CardBackground(wash: .amber) { contenido }
        case .bien, .apagado:
            CardBackground(wash: .green) { contenido }
        }
    }

    private var contenido: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: estado.colorHex))
                    .frame(width: 7, height: 7)
                Text(verbatim: titulo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TableroColor.texto)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            Text(verbatim: vigilantes.isEmpty ? "Sin vigilantes conectados"
                                              : "\(bien) de \(vigilantes.count) vigilantes bien")
                .font(.system(size: 11))
                .foregroundColor(TableroColor.suave)
                .lineLimit(1)
            if let revisado {
                Text(verbatim: "Revisado \(TableroTiempo.hace(TableroTiempo.minutos(desde: revisado)))")
                    .font(.system(size: 11))
                    .foregroundColor(TableroColor.tenue)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 1b. Sesiones de Claude Code

/// Sesiones de Claude Code abiertas en este Mac (datos reales de Coucou). Sin
/// sesiones, muestra el equipo como en la foto: "Sin sesiones · carga · disco".
struct TableroSesiones: View {
    @ObservedObject var state: AppState
    let equipo: TableroEquipo

    private var sesiones: [AgentTask] {
        state.tasks.filter { !$0.isIntegration && $0.source == .claudeCode }
    }

    var body: some View {
        CardBackground(wash: nil) {
            if sesiones.isEmpty {
                VStack(spacing: 4) {
                    Text(verbatim: "Sin sesiones")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TableroColor.texto)
                    Text(verbatim: "\(equipo.nombre) · carga \(tableroDecimal(equipo.carga)) · disco \(TableroTiempo.porcentaje(equipo.disco))")
                        .font(.system(size: 11))
                        .foregroundColor(TableroColor.suave)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: sesiones.count == 1 ? "1 sesión" : "\(sesiones.count) sesiones")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TableroColor.texto)
                    ForEach(sesiones.prefix(2)) { s in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: s.color))
                                .frame(width: 6, height: 6)
                            Text(verbatim: s.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TableroColor.texto)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text(verbatim: Self.rotulo(s.state))
                                .font(.system(size: 10))
                                .foregroundColor(TableroColor.suave)
                                .fixedSize()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    static func rotulo(_ estado: BotState) -> String {
        switch estado {
        case .working:   return "trabajando"
        case .thinking:  return "pensando"
        case .searching: return "buscando"
        case .approval:  return "pide permiso"
        case .question:  return "pregunta"
        case .error:     return "error"
        case .finished:  return "terminó"
        case .ratelimit: return "en límite"
        case .sleeping:  return "dormida"
        case .idle, .dizzy: return "en espera"
        }
    }
}

// MARK: - 2a. Consumos

/// Claude sale del uso del plan de Coucou, Vercel y GitHub de TableroFuentes
/// (TableroArmado.consumos). Lo que no tiene fuente dice "sin datos".
struct TableroConsumos: View {
    let consumos: [TableroConsumo]

    var body: some View {
        TableroTarjeta(titulo: "Consumos", punto: .bien, muestra: false) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(consumos) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(verbatim: c.nombre)
                                .font(.system(size: 11))
                                .foregroundColor(TableroColor.suave)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(verbatim: c.valor)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(TableroColor.texto)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        if let f = c.fraccion {
                            TableroBarraUso(fraccion: f, colorHex: c.colorHex)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 2b. Novedades

struct TableroNovedades: View {
    let novedades: [TableroNovedad]

    var body: some View {
        // Solo la cifra, como en Pendientes: "4 hoy" no cabe junto a la etiqueta
        // "muestra" en la tarjeta angosta y salía cortado ("4 h...").
        TableroTarjeta(titulo: "Novedades", detalle: "\(novedades.count)", punto: .falla) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(novedades.prefix(5)) { n in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: n.estado.colorHex))
                            .frame(width: 5, height: 5)
                        Text(verbatim: n.texto)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TableroColor.texto)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(verbatim: TableroTiempo.corto(n.minutosAtras))
                            .font(.system(size: 10))
                            .foregroundColor(TableroColor.tenue)
                            .fixedSize()
                    }
                }
            }
        }
    }
}

// MARK: - 2c. Pendientes

/// Con Recordatorios: los recordatorios sin terminar; el check los marca hechos
/// en la app Recordatorios y el reloj los esconde una hora en el tablero.
/// Sin permiso: la muestra y el boton para conectar Recordatorios.
struct TableroPendientes: View {
    @ObservedObject var store: PendientesStore

    var body: some View {
        let visibles = store.visibles()
        let punto: TableroEstado = visibles.contains(where: { $0.vencido }) ? .falla : .aviso
        TableroTarjeta(titulo: "Pendientes", detalle: "\(visibles.count)", punto: punto,
                       muestra: !store.usaRecordatorios) {
            VStack(alignment: .leading, spacing: 6) {
                if store.usaRecordatorios {
                    if visibles.isEmpty {
                        Text(verbatim: store.cargado ? "Nada pendiente" : "Leyendo Recordatorios…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TableroColor.suave)
                    }
                    filas(visibles, cuantas: 3)
                } else {
                    if visibles.isEmpty {
                        boton("Volver a la muestra") { store.restaurarMuestra() }
                    }
                    filas(visibles, cuantas: 2)
                    if store.accesoNegado {
                        Text(verbatim: "Actívalo en Configuración › Privacidad y seguridad › Recordatorios")
                            .font(.system(size: 10))
                            .foregroundColor(TableroColor.suave)
                            .lineLimit(2)
                    } else {
                        boton("Usar mis Recordatorios") {
                            Task { await store.conectarRecordatorios() }
                        }
                    }
                }
            }
        }
    }

    private func filas(_ visibles: [Pendiente], cuantas: Int) -> some View {
        ForEach(visibles.prefix(cuantas)) { p in
            TableroFilaPendiente(pendiente: p,
                                 onHecho: { store.completar(p.id) },
                                 onLuego: { store.posponer(p.id) })
        }
    }

    private func boton(_ texto: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(verbatim: texto)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(TableroColor.texto)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

struct TableroFilaPendiente: View {
    let pendiente: Pendiente
    let onHecho: () -> Void
    let onLuego: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: pendiente.vencido ? TableroEstado.falla.colorHex : "#60A5FA"))
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: pendiente.titulo)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TableroColor.texto)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: pendiente.detalle)
                    .font(.system(size: 10))
                    .foregroundColor(TableroColor.suave)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Button(action: onHecho) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "#22C55E"))
            }
            .buttonStyle(.plain)
            .help("Hecho")
            Button(action: onLuego) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundColor(TableroColor.suave)
            }
            .buttonStyle(.plain)
            .help("Recordar en una hora")
        }
    }
}

// MARK: - 3a. Deploys y pushes

struct TableroActividadTarjeta: View {
    let items: [TableroActividad]
    var muestra: Bool = false

    private var ordenados: [TableroActividad] {
        items.sorted { $0.minutosAtras < $1.minutosAtras }
    }

    var body: some View {
        TableroTarjeta(titulo: "Actividad", detalle: "deploys · pushes", punto: .bien, muestra: muestra) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(ordenados.prefix(4)) { a in
                    HStack(spacing: 6) {
                        Image(systemName: a.tipo == .deploy ? "arrow.up.circle.fill" : "arrow.triangle.branch")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: a.estado.colorHex))
                            .frame(width: 12)
                        Text(verbatim: a.proyecto)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TableroColor.texto)
                            .lineLimit(1)
                            .fixedSize()
                        Text(verbatim: a.detalle)
                            .font(.system(size: 10))
                            .foregroundColor(TableroColor.suave)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(verbatim: TableroTiempo.corto(a.minutosAtras))
                            .font(.system(size: 10))
                            .foregroundColor(TableroColor.tenue)
                            .fixedSize()
                    }
                }
            }
        }
    }
}

// MARK: - 3b. MacBook

struct TableroEquipoTarjeta: View {
    let equipo: TableroEquipo
    var muestra: Bool = false

    /// La carga se mide contra los nucleos del Mac: 1,0 por nucleo es lleno.
    private var nucleos: Double { Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)) }

    var body: some View {
        TableroTarjeta(titulo: equipo.nombre, detalle: "carga \(tableroDecimal(equipo.carga))", punto: .bien,
                       muestra: muestra) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    TableroMedida(nombre: "Memoria", fraccion: equipo.memoria)
                    TableroMedida(nombre: "Disco", fraccion: equipo.disco)
                }
                VStack(alignment: .leading, spacing: 9) {
                    if let bateria = equipo.bateria {
                        TableroMedida(nombre: equipo.cargando ? "Batería · cargando" : "Batería",
                                      fraccion: bateria, invertida: true)
                    }
                    TableroMedida(nombre: "Carga", fraccion: min(equipo.carga / nucleos, 1),
                                  valor: tableroDecimal(equipo.carga))
                }
            }
        }
    }
}

/// Un numero con su barra. Con `invertida`, poco es malo (la bateria).
struct TableroMedida: View {
    let nombre: String
    let fraccion: Double
    var invertida: Bool = false
    var valor: String? = nil

    private var colorHex: String {
        let nivel = invertida ? 1 - fraccion : fraccion
        if nivel < 0.6 { return "#22C55E" }
        if nivel < 0.85 { return "#F59E0B" }
        return "#F4505E"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(verbatim: nombre)
                    .font(.system(size: 11))
                    .foregroundColor(TableroColor.suave)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: valor ?? TableroTiempo.porcentaje(fraccion))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TableroColor.texto)
                    .fixedSize()
            }
            TableroBarraUso(fraccion: fraccion, colorHex: colorHex)
        }
    }
}

// MARK: - 4. Barra de vigilantes y equipos

struct TableroBarra: View {
    let vigilantes: [TableroVigilante]
    let equipo: TableroEquipo

    private var bien: Int { vigilantes.filter { $0.estado == .bien }.count }
    private var malos: [TableroVigilante] { vigilantes.filter { $0.estado == .falla || $0.estado == .aviso } }

    var body: some View {
        HStack(spacing: 14) {
            TableroPunto(texto: "\(bien) vigilantes OK", estado: .bien)
            ForEach(malos.prefix(2)) { v in
                TableroPunto(texto: v.rotulo,
                             estado: v.estado)
            }
            Spacer(minLength: 8)
            TableroPunto(texto: equipo.nombre, estado: .bien, suave: true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#141518"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.035), lineWidth: 1)
                )
        )
    }
}

struct TableroPunto: View {
    let texto: String
    let estado: TableroEstado
    var suave: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: estado.colorHex))
                .frame(width: 6, height: 6)
            Text(verbatim: texto)
                .font(.system(size: 11, weight: suave ? .regular : .semibold))
                .foregroundColor(suave ? TableroColor.suave : TableroColor.texto)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

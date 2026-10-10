import Foundation
import IOKit.ps

// MARK: - Tablero: fuentes reales
//
// Llena las estructuras de TableroDatos con datos de verdad:
//   - El MacBook (carga, memoria, disco, bateria), medido en el propio Mac.
//   - Deploys de Vercel de las ultimas 24 h, con el token de Ajustes.
//   - Los repos de GitHub con su ultimo push y el CI de la rama principal,
//     con el token de Ajustes (permisos de solo lectura).
// Solo trabaja mientras el tablero esta a la vista: TableroView llama a
// vigilar() desde .task y la tarea se cancela al cambiar de vista o cerrar la
// isla, asi que con el panel cerrado no gasta nada.

@MainActor
final class TableroFuentes: ObservableObject {
    static let shared = TableroFuentes()

    /// El MacBook, medido cada 5 s. nil hasta la primera medida.
    @Published private(set) var equipo: TableroEquipo?
    /// Deploys de Vercel creados en las ultimas 24 h. nil sin token o sin respuesta.
    @Published private(set) var deploysHoy: Int?
    /// Repos de GitHub, el push mas reciente primero. Vacio sin token.
    @Published private(set) var repos: [TableroRepo] = []
    /// Ultima vuelta completa de vigilar().
    @Published private(set) var revisado: Date?

    private var ultimaRed = Date.distantPast
    private var ultimoDisco = Date.distantPast
    private var disco: Double = 0

    private init() {}

    /// Mide el Mac cada 5 s y consulta Vercel y GitHub cada 2 min, hasta que
    /// cancelen la tarea.
    func vigilar() async {
        while !Task.isCancelled {
            medirEquipo()
            if Date().timeIntervalSince(ultimaRed) >= 120 {
                ultimaRed = Date()
                await refrescarRed()
            }
            revisado = Date()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func medirEquipo() {
        // El disco cambia despacio y medirlo cuesta mas: una vez por minuto.
        if Date().timeIntervalSince(ultimoDisco) >= 60 {
            disco = TableroEquipoLector.disco()
            ultimoDisco = Date()
        }
        let bateria = TableroEquipoLector.bateria()
        equipo = TableroEquipo(nombre: bateria == nil ? "Mac" : "MacBook",
                               carga: TableroEquipoLector.carga(),
                               memoria: TableroEquipoLector.memoria(),
                               disco: disco,
                               bateria: bateria?.nivel,
                               cargando: bateria?.cargando ?? false)
    }

    private func refrescarRed() async {
        let filtro = AppState.shared.vercelProjectFilter
        let tokenVercel = KeychainStore.shared.get("vercel-token")
        let tokenGitHub = KeychainStore.shared.get("github-token")
        async let vercel = TableroRed.deploysUltimas24h(token: tokenVercel, filtro: filtro)
        async let github = TableroRed.repos(token: tokenGitHub)
        let (deploys, lista) = await (vercel, github)
        // Si la consulta falla, se queda lo ultimo que llego; si quitaron el
        // token, se borra.
        if let deploys { deploysHoy = deploys } else if tokenVercel == nil { deploysHoy = nil }
        if let lista { repos = lista } else if tokenGitHub == nil { repos = [] }
    }
}

// MARK: - El Mac

enum TableroEquipoLector {
    /// Carga promedio del ultimo minuto, como `uptime`.
    static func carga() -> Double {
        var cargas = [Double](repeating: 0, count: 3)
        return getloadavg(&cargas, 3) > 0 ? cargas[0] : 0
    }

    /// Memoria usada como la cuenta el Monitor de Actividad (memoria de apps,
    /// cableada y comprimida) sobre la memoria fisica.
    static func memoria() -> Double {
        var stats = vm_statistics64_data_t()
        var cuenta = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let resultado = withUnsafeMutablePointer(to: &stats) { puntero in
            puntero.withMemoryRebound(to: integer_t.self, capacity: Int(cuenta)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &cuenta)
            }
        }
        var pagina: vm_size_t = 0
        host_page_size(host, &pagina)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard resultado == KERN_SUCCESS, pagina > 0, total > 0 else { return 0 }
        let apps = max(0, Double(stats.internal_page_count) - Double(stats.purgeable_count))
        let paginas = apps + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return min(max(paginas * Double(pagina) / total, 0), 1)
    }

    /// Lo usado del disco de arranque, contando como libre lo que macOS puede
    /// liberar (igual que el Finder).
    static func disco() -> Double {
        let raiz = URL(fileURLWithPath: "/")
        guard let valores = try? raiz.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                              .volumeAvailableCapacityForImportantUsageKey]),
              let total = valores.volumeTotalCapacity, total > 0,
              let libre = valores.volumeAvailableCapacityForImportantUsage else { return 0 }
        return min(max(1 - Double(libre) / Double(total), 0), 1)
    }

    /// Nivel de la bateria interna (0...1) y si esta cargando. nil sin bateria.
    static func bateria() -> (nivel: Double, cargando: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let fuentes = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for fuente in fuentes {
            guard let datos = IOPSGetPowerSourceDescription(info, fuente)?.takeUnretainedValue() as? [String: Any],
                  (datos["Type"] as? String) == "InternalBattery",
                  let actual = datos["Current Capacity"] as? Int,
                  let maximo = datos["Max Capacity"] as? Int, maximo > 0 else { continue }
            let cargando = (datos["Is Charging"] as? Bool) ?? false
            return (min(Double(actual) / Double(maximo), 1), cargando)
        }
        return nil
    }
}

// MARK: - Vercel y GitHub

enum TableroRed {
    /// Deploys de Vercel creados en las ultimas 24 h, de los proyectos elegidos
    /// en Ajustes (todos si no hay filtro). nil sin token o si falla.
    static func deploysUltimas24h(token: String?, filtro: Set<String>) async -> Int? {
        guard let token else { return nil }
        let desde = Int64((Date().timeIntervalSince1970 - 86_400) * 1000)
        guard let url = URL(string: "https://api.vercel.com/v6/deployments?limit=100&since=\(desde)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let respuesta = try? await URLSession.shared.data(for: req),
              (respuesta.1 as? HTTPURLResponse)?.statusCode == 200,
              let raiz = try? JSONSerialization.jsonObject(with: respuesta.0) as? [String: Any],
              let lista = raiz["deployments"] as? [[String: Any]] else { return nil }
        guard !filtro.isEmpty else { return lista.count }
        return lista.filter { ($0["name"] as? String).map(filtro.contains) ?? false }.count
    }

    /// Solo pide datos del repo (nombre, ultimo push) y el estado del CI: basta
    /// con los permisos de solo lectura que pide Coucou para GitHub.
    static let consultaRepos = """
    query {
      viewer {
        repositories(first: 6, ownerAffiliations: [OWNER], orderBy: {field: PUSHED_AT, direction: DESC}) {
          nodes {
            name nameWithOwner pushedAt isArchived
            defaultBranchRef {
              name
              target { ... on Commit { statusCheckRollup { state } } }
            }
          }
        }
      }
    }
    """

    /// Repos del usuario, el push mas reciente primero. nil sin token o si falla.
    static func repos(token: String?) async -> [TableroRepo]? {
        guard let token,
              let url = URL(string: "https://api.github.com/graphql"),
              let cuerpo = try? JSONSerialization.data(withJSONObject: ["query": consultaRepos]) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = cuerpo
        guard let respuesta = try? await URLSession.shared.data(for: req),
              (respuesta.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return leerRepos(respuesta.0)
    }

    static func leerRepos(_ data: Data) -> [TableroRepo]? {
        guard let raiz = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let datos = raiz["data"] as? [String: Any],
              let viewer = datos["viewer"] as? [String: Any],
              let conexion = viewer["repositories"] as? [String: Any],
              let nodos = conexion["nodes"] as? [[String: Any]] else { return nil }
        let fechas = ISO8601DateFormatter()
        return nodos.compactMap { nodo -> TableroRepo? in
            guard let nombre = nodo["name"] as? String,
                  let completo = nodo["nameWithOwner"] as? String,
                  (nodo["isArchived"] as? Bool) != true,
                  let texto = nodo["pushedAt"] as? String,
                  let push = fechas.date(from: texto) else { return nil }
            let rama = nodo["defaultBranchRef"] as? [String: Any]
            let commit = rama?["target"] as? [String: Any]
            let rollup = commit?["statusCheckRollup"] as? [String: Any]
            return TableroRepo(id: completo, nombre: nombre,
                               rama: (rama?["name"] as? String) ?? "main",
                               push: push,
                               ci: TableroRepo.CI(rawGitHub: rollup?["state"] as? String))
        }
    }
}

// MARK: - Lo que pinta cada tarjeta

/// Arma las listas de las tarjetas a partir de Coucou (AppState) y de las
/// fuentes del tablero. Lo que no tiene fuente conectada vuelve vacio o nil, y
/// la tarjeta decide si muestra la muestra o "sin datos".
@MainActor
enum TableroArmado {
    /// Deploys de Vercel (los ultimos que trajo Coucou) y el ultimo push de
    /// cada repo de GitHub, el mas reciente primero.
    static func actividad(state: AppState, repos: [TableroRepo], ahora: Date = Date()) -> [TableroActividad] {
        let filtro = state.vercelProjectFilter
        var lista: [TableroActividad] = []
        for d in state.vercelDeployments where filtro.isEmpty || filtro.contains(d.projectName) {
            let cancelado = d.state == "CANCELED"
            let rotulo = d.isSuccess ? "Listo" : (cancelado ? "Cancelado" : "Falló")
            let mensaje = d.commitMessage?.split(separator: "\n").first.map(String.init)
            lista.append(TableroActividad(
                id: "deploy-\(d.id)", tipo: .deploy, proyecto: d.projectName,
                detalle: [rotulo, mensaje].compactMap { $0 }.joined(separator: " · "),
                estado: d.isSuccess ? .bien : (cancelado ? .apagado : .falla),
                minutosAtras: TableroTiempo.minutos(desde: d.createdAt, ahora: ahora)))
        }
        for r in repos {
            lista.append(TableroActividad(
                id: "push-\(r.id)", tipo: .push, proyecto: r.nombre,
                detalle: "\(r.rama) · \(r.ci.texto)",
                estado: r.ci == .sinCI ? .bien : r.ci.estado,
                minutosAtras: TableroTiempo.minutos(desde: r.push, ahora: ahora)))
        }
        return lista.sorted { $0.minutosAtras < $1.minutosAtras }
    }

    /// Las cuatro barras de Consumos. Sin fuente: "sin datos" y sin barra.
    static func consumos(state: AppState, deploysHoy: Int?, repos: [TableroRepo]) -> [TableroConsumo] {
        var lista: [TableroConsumo] = []
        let uso = state.claudePlanUsage
        lista.append(consumoClaude(id: "claude-sesion", nombre: "Claude sesión", ventana: uso?.fiveHour))
        lista.append(consumoClaude(id: "claude-semana", nombre: "Claude semana", ventana: uso?.sevenDay))

        // Vercel Hobby permite 100 deploys al dia.
        if let n = deploysHoy {
            lista.append(TableroConsumo(id: "vercel", nombre: "Vercel", valor: "\(n) de 100 hoy",
                                        fraccion: Double(n) / 100, colorHex: "#A78BFA"))
        } else {
            lista.append(sinDatos(id: "vercel", nombre: "Vercel"))
        }

        // GitHub: cuantos repos tienen el CI de la rama principal en verde.
        let conCI = repos.filter { $0.ci != .sinCI }
        if conCI.isEmpty {
            lista.append(repos.isEmpty ? sinDatos(id: "github", nombre: "GitHub CI")
                                       : TableroConsumo(id: "github", nombre: "GitHub CI", valor: "sin CI",
                                                        fraccion: nil, colorHex: "#38BDF8"))
        } else {
            let verdes = conCI.filter { $0.ci == .verde }.count
            let color: String
            if conCI.contains(where: { $0.ci == .falla }) {
                color = TableroEstado.falla.colorHex
            } else if conCI.contains(where: { $0.ci == .corriendo }) {
                color = TableroEstado.aviso.colorHex
            } else {
                color = TableroEstado.bien.colorHex
            }
            lista.append(TableroConsumo(id: "github", nombre: "GitHub CI",
                                        valor: "\(verdes) de \(conCI.count) en verde",
                                        fraccion: Double(verdes) / Double(conCI.count), colorHex: color))
        }
        return lista
    }

    private static func consumoClaude(id: String, nombre: String, ventana: PlanWindow?) -> TableroConsumo {
        guard let ventana else { return sinDatos(id: id, nombre: nombre) }
        let pct = ClaudePlanGauge.effectivePct(ventana)
        return TableroConsumo(id: id, nombre: nombre, valor: "\(Int(pct.rounded()))%",
                              fraccion: pct / 100, colorHex: ClaudePlanGauge.color(for: pct))
    }

    private static func sinDatos(id: String, nombre: String) -> TableroConsumo {
        TableroConsumo(id: id, nombre: nombre, valor: "sin datos", fraccion: nil, colorHex: TableroEstado.apagado.colorHex)
    }

    /// Vigilantes: solo los que tienen fuente. Claude por el uso del plan,
    /// GitHub por el CI, Vercel por el ultimo deploy de cada proyecto, y la
    /// bateria y el disco del Mac.
    static func vigilantes(state: AppState, repos: [TableroRepo], equipo: TableroEquipo?) -> [TableroVigilante] {
        var lista: [TableroVigilante] = []

        if let uso = state.claudePlanUsage, let pct = ClaudePlanGauge.dominantPct(uso) {
            lista.append(TableroVigilante(id: "claude", nombre: "Claude",
                                          estado: pct >= 90 ? .falla : (pct >= 75 ? .aviso : .bien),
                                          problema: "al \(Int(pct.rounded()))% del límite"))
        }

        if !repos.isEmpty {
            let estado: TableroEstado
            if repos.contains(where: { $0.ci == .falla }) {
                estado = .falla
            } else if repos.contains(where: { $0.ci == .corriendo }) {
                estado = .aviso
            } else {
                estado = .bien
            }
            lista.append(TableroVigilante(id: "github", nombre: "GitHub", estado: estado,
                                          problema: estado == .falla ? "CI con fallas" : "CI corriendo"))
        }

        let filtro = state.vercelProjectFilter
        let deploys = state.vercelDeployments.filter { filtro.isEmpty || filtro.contains($0.projectName) }
        if !deploys.isEmpty {
            // El mas reciente de cada proyecto manda (la lista viene del mas nuevo al mas viejo).
            var vistos = Set<String>()
            let ultimos = deploys.filter { vistos.insert($0.projectName).inserted }
            let falla = ultimos.contains(where: { !$0.isSuccess && $0.state != "CANCELED" })
            lista.append(TableroVigilante(id: "vercel", nombre: "Vercel", estado: falla ? .falla : .bien,
                                          problema: "un deploy falló"))
        }

        if let equipo {
            if let nivel = equipo.bateria {
                let estado: TableroEstado = equipo.cargando ? .bien
                                          : nivel < 0.1 ? .falla : (nivel < 0.2 ? .aviso : .bien)
                lista.append(TableroVigilante(id: "bateria", nombre: "Batería", estado: estado,
                                              problema: "baja (\(TableroTiempo.porcentaje(nivel)))"))
            }
            // Un disco casi lleno no es una falla del disco: se dice lo que pasa.
            lista.append(TableroVigilante(id: "disco", nombre: "Disco",
                                          estado: equipo.disco > 0.9 ? .falla : (equipo.disco > 0.8 ? .aviso : .bien),
                                          problema: "casi lleno (\(TableroTiempo.porcentaje(equipo.disco)))"))
        }
        return lista
    }
}

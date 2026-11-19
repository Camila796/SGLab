<?php
// Recibe el reporte que envía ps/registro.ps1 y lo guarda en la base de datos.
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/../Models/Database.php';
require_once __DIR__ . '/../Models/Registro.php';
require_once __DIR__ . '/../Models/Equipo.php';

// Registro.idUsuario es obligatorio: sin cédula conocida se usa el usuario del sistema.
const ID_USUARIO_SISTEMA = 1;

function enviarRespuesta($statusCode, $mensaje, $datos = null) {
    http_response_code($statusCode);
    $respuesta = ['mensaje' => $mensaje];
    if ($datos) {
        $respuesta['datos'] = $datos;
    }
    echo json_encode($respuesta, JSON_UNESCAPED_UNICODE);
    exit;
}

function buscarId($sql, $valor) {
    $stmt = Database::getConnection('admin')->prepare($sql);
    $stmt->execute([$valor]);
    return $stmt->fetchColumn() ?: null;
}

try {
    // 1. Seguridad y método
    Dotenv\Dotenv::createImmutable(__DIR__ . '/..')->safeLoad();
    $claveEsperada = $_ENV['API_SECRET_KEY'] ?? '';
    if ($claveEsperada === '' || str_starts_with($claveEsperada, 'CAMBIAR')) {
        error_log('api_registro: API_SECRET_KEY no está configurada en .env');
        enviarRespuesta(503, 'La API no está configurada en el servidor.');
    }
    if (!hash_equals($claveEsperada, $_SERVER['HTTP_X_API_KEY'] ?? '')) {
        enviarRespuesta(401, 'Acceso no autorizado.');
    }
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        enviarRespuesta(405, 'Método no permitido.');
    }

    // 2. Leer y validar el reporte
    $data = json_decode(file_get_contents('php://input'), true);
    if (!is_array($data)) {
        enviarRespuesta(400, 'El cuerpo de la petición debe ser JSON válido.');
    }
    $faltantes = array_filter(
        ['serial', 'hostname', 'cpu', 'ram_gb', 'disco_tipo', 'disco_total_gb'],
        fn($campo) => !isset($data[$campo]) || trim((string)$data[$campo]) === ''
    );
    if ($faltantes) {
        enviarRespuesta(400, 'Faltan campos obligatorios.', ['campos' => array_values($faltantes)]);
    }

    $serial = trim((string)$data['serial']);
    $hostname = trim((string)$data['hostname']);
    $cpu = mb_substr((string)$data['cpu'], 0, 100);
    $ram = (int)round((float)$data['ram_gb']);
    $discoTipo = mb_substr((string)$data['disco_tipo'], 0, 50);
    $discoTotal = (int)round((float)$data['disco_total_gb']);
    $idLaboratorioReportado = buscarId(
        'SELECT idLaboratorio FROM Laboratorios WHERE nombre = ?',
        (string)($data['laboratorio'] ?? '')
    );

    // 3. Buscar el equipo por serial; si es nuevo, darlo de alta
    $equipo = Equipo::obtenerPorSerial($serial);
    $equipoNuevo = !$equipo;
    if ($equipoNuevo) {
        if (Equipo::obtenerPorHostname($hostname)) {
            enviarRespuesta(409, 'Ya existe otro equipo con ese hostname y distinto serial.', [
                'hostname' => $hostname,
                'serial' => $serial,
            ]);
        }
        if (!Equipo::crearEquipo($serial, $hostname, $cpu, $ram, $discoTipo, $discoTotal, $idLaboratorioReportado)) {
            enviarRespuesta(500, 'No se pudo dar de alta el equipo.');
        }
        $equipo = Equipo::obtenerPorSerial($serial);
    } else {
        // Mantener al día el hardware sin perder el laboratorio ya asignado.
        // Si falla (hostname repetido) se registra en el log y el reporte igual se guarda.
        Equipo::actualizarEquipo(
            $equipo['idEquipo'], $hostname, $cpu, $ram, $discoTipo, $discoTotal,
            $equipo['idLaboratorio'] ?? $idLaboratorioReportado
        );
    }

    // 4. Identificar al responsable por cédula
    $idUsuario = buscarId('SELECT id FROM Usuarios WHERE ci = ?', (int)($data['cedula'] ?? 0))
        ?? ID_USUARIO_SISTEMA;

    // 5. Guardar el registro (la descripción tiene un máximo de 255 caracteres)
    $descripcion = sprintf(
        'Reporte automático | Usuario: %s | SO: %s (%s) | Red: /%s gw %s | Uso CPU %s%% RAM %s%% Disco %s%%',
        $data['usuario_windows'] ?? '?',
        $data['so'] ?? '?',
        $data['so_version'] ?? '?',
        $data['mascara'] ?? '?',
        $data['gateway'] ?? '?',
        $data['cpu_uso'] ?? '?',
        $data['ram_uso'] ?? '?',
        $data['disco_uso'] ?? '?'
    );

    $registro = new Registro([
        'idEquipo'    => $equipo['idEquipo'],
        'idUsuario'   => $idUsuario,
        'fecha'       => time(),
        'estado'      => filter_var($data['estado'] ?? false, FILTER_VALIDATE_BOOLEAN) ? 1 : 0,
        'IP'          => filter_var($data['ip'] ?? '', FILTER_VALIDATE_IP) ?: null,
        'diskFree'    => isset($data['disco_libre_gb']) ? (int)$data['disco_libre_gb'] : null,
        'descripcion' => mb_substr($descripcion, 0, 255),
    ]);

    if (!$registro->guardar()) {
        enviarRespuesta(500, 'Error al guardar el registro en la base de datos.');
    }

    enviarRespuesta(201, 'Registro guardado.', [
        'idEquipo' => $equipo['idEquipo'],
        'equipoNuevo' => $equipoNuevo,
        'laboratorioAsignado' => $equipo['idLaboratorio'] !== null,
    ]);
} catch (Throwable $e) {
    error_log('Error en api_registro.php: ' . $e->getMessage());
    enviarRespuesta(500, 'Ocurrió un error interno en el servidor.');
}

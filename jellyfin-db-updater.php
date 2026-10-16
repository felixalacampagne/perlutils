<?php
// Enforce secure POST constraints
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('HTTP/1.1 405 Method Not Allowed');
    exit('Only POST requests allowed.');
}

$dbPath = '\\nasug\docker\jellyfin-server\config\data\jellyfin.db'; 
$secret_token = "ChooseYourOwnSecureSecretKey"; // Must match your Jellyfin plugin value exactly

// 1. Authenticate Request using the Custom Authorization Header
$headers = getallheaders();
$incoming_token = $headers['X-Secret-Token'] ?? $headers['x-secret-token'] ?? null;

if (!$incoming_token || $incoming_token !== $secret_token) {
    header('HTTP/1.1 401 Unauthorized');
    exit('Unauthorized access.');
}

// 2. Read the raw JSON payload arriving directly from Jellyfin
$input = file_get_contents('php://input');
$payload = json_decode($input, true);

// Safely extract properties handling nested payload varieties
$raw_item = $payload['ItemId'] ?? $payload['Item']['Id'] ?? null;
$raw_user = $payload['UserId'] ?? $payload['User']['Id'] ?? null;
$raw_time = $payload['UtcTimestamp'] ?? null;

if (!$raw_item || !$raw_user) {
    header('HTTP/1.1 400 Bad Request');
    exit('Missing required identifier context properties.');
}

// 3. Helper Function to reformat raw 32-char hex strings to uppercase 8-4-4-4-12 GUIDs
function formatToUppercaseGuid($string) {
    $clean = str_replace('-', '', $string); // Strip any existing hyphens if present
    if (strlen($clean) !== 32) return strtoupper($string); // Safety fallback
    
    // Group characters cleanly using regex pattern tracking chunks
    $pattern = '/^([0-9a-fA-F]{8})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{4})([0-9a-fA-F]{12})$/';
    $replacement = '$1-$2-$3-$4-$5';
    return strtoupper(preg_replace($pattern, $replacement, $clean));
}

$itemId = formatToUppercaseGuid($raw_item);
$userId = formatToUppercaseGuid($raw_user);

// 4. Sanitize and reformat the incoming timestamp string
// Inputs look like "2026-10-15T13:55:03.1720427Z" -> Output becomes "2026-10-15 13:55:03"
if ($raw_time) {
    $time_parts = explode('.', $raw_time);
    $datePlayed = str_replace('T', ' ', $time_parts[0]);
} else {
    // Generate an instantaneous fallback timestamp matching exact structure
    gmdate_default_timezone_set('UTC');
    $datePlayed = date('Y-m-d H:i:s');
}

// 5. Connect and Execute the raw Database transaction via UNC pathing


try {
    $pdo = new PDO("sqlite:" . $dbPath);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // Explicitly modify the targeted track properties on the UserDatas map row
    $sql = "UPDATE UserDatas 
            SET LastPlayedDate = :date_played, Played = 1, PlayCount = PlayCount + 1
            WHERE key = :item_id AND UserId = :user_id";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([
        ':date_played' => $datePlayed,
        ':item_id'     => $itemId,
        ':user_id'     => $userId
    ]);

    header('Content-Type: application/json');
    echo json_encode([
        "status" => "success",
        "processed_item" => $itemId,
        "processed_user" => $userId,
        "processed_date" => $datePlayed,
        "rows_affected" => $stmt->rowCount()
    ]);

} catch (PDOException $e) {
    header('HTTP/1.1 500 Internal Server Error');
    exit('Database update failed: ' . $e->getMessage());
}

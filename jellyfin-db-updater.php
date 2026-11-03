<?php
function log_to_apache($message) {
    error_log("[Jellyfin Updater] " . $message);
}
$secret_token = "ChooseYourOwnSecureSecretKey";
$queueFile = 'C:/Development/accountDB/jellyfin_queue.csv';

// Enforce secure POST constraints
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('HTTP/1.1 405 Method Not Allowed');
    log_to_apache("Non POST request");
    exit('Only POST requests allowed.');
}

// 1. Extract headers safely for older PHP versions
$headers = getallheaders();
$incoming_token = null;

if (isset($headers['X-Secret-Token'])) {
    $incoming_token = $headers['X-Secret-Token'];
} elseif (isset($headers['x-secret-token'])) {
    $incoming_token = $headers['x-secret-token'];
}

if (!$incoming_token || $incoming_token !== $secret_token) {
    header('HTTP/1.1 401 Unauthorized');
    log_to_apache("Token mismatch");
    exit('Unauthorized access.');
}

// 2. Read raw payload input
$input = file_get_contents('php://input');
$payload = json_decode($input, true);

// 3. Extract payload properties safely without ?? operators
$raw_item = null;
if (isset($payload['ItemId'])) {
    $raw_item = $payload['ItemId'];
} elseif (isset($payload['Item']['Id'])) {
    $raw_item = $payload['Item']['Id'];
}

$raw_user = null;
if (isset($payload['UserId'])) {
    $raw_user = $payload['UserId'];
} elseif (isset($payload['User']['Id'])) {
    $raw_user = $payload['User']['Id'];
}

$raw_time = isset($payload['UtcTimestamp']) ? $payload['UtcTimestamp'] : null;

if (!$raw_item || !$raw_user) {
    header('HTTP/1.1 400 Bad Request');
    log_to_apache("Missing ItemId or UserId");
    exit('Missing required payload elements.');
}

$position   = isset($payload['PlaybackPositionTicks']) ? (float)$payload['PlaybackPositionTicks'] : 0;
$runtime    = isset($payload['RunTimeTicks']) ? (float)$payload['RunTimeTicks'] : 0;

$itemId = formatToUppercaseGuid($raw_item);
$userId = formatToUppercaseGuid($raw_user);

// log_to_apache("Position:" . $position . " Runtime: " . $runtime);

// PROGRESS CHECK: Only update database if the user has listened to at least 90% of the track
// This acts as a robust completion check for automatic playlist transitions
$hasPlayedToCompletion = false;
if ($runtime > 0) {
    $completionPercentage = ($position / $runtime) * 100;
    // log_to_apache("Progress:" . $completionPercentage);
    if ($completionPercentage >= 90 && $completionPercentage < 92) {
        $hasPlayedToCompletion = true;
    }
}

if (!$hasPlayedToCompletion) {
    header('Content-Type: application/json');
    echo json_encode(["status" => "ignored", "message" => "Track progress has not met completion threshold."]);
    // log_to_apache($itemId . " Ignoring position: " . $position . ": TOO SOON");
    exit('ignored');
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



// Extract just the calendar date (YYYY-MM-DD) to prevent spamming within the same listen session
$datePart = substr($datePlayed, 0, 10); 

// 2. DEDUPLICATION CHECK: Read the file if it exists
if (file_exists($queueFile)) {
   // Open the file with a shared read lock
   $fileHandle = fopen($queueFile, 'r');
   if ($fileHandle) {
      while (($line = fgets($fileHandle)) !== false) {
          $parts = explode(',', trim($line));
          if (count($parts) === 3) {
              $existingItem = $parts[0];
              $existingUser = $parts[1];
              $existingDate = substr($parts[2], 0, 10);
              
              // If this item was already logged for this user today, skip it
              if ($existingItem === $itemId && $existingUser === $userId && $existingDate === $datePart) {
                  fclose($fileHandle);
                  header('Content-Type: application/json');
                  echo json_encode(["status" => "skipped", "message" => "Duplicate entry blocked."]);
                  //log_to_apache($itemId . " Ignoring position: " . $position . ": ALREADY WRITTEN");
                  exit;
              }
          }
      }
      fclose($fileHandle);
   }
}

// Format the data into a single comma-separated line
$logLine = "$itemId,$userId,$datePlayed" . PHP_EOL;

// Save it to a local queue file on the Windows 11 drive
file_put_contents($queueFile, $logLine, FILE_APPEND | LOCK_EX);
log_to_apache($itemId . " Ignoring position: " . $position . ": QUEUED");
echo json_encode(["status" => "queued"]);
?>
ok
<?php
/**
 * Shared helpers for the TechStore REST API.
 */

// Never print PHP warnings into a response: they would break the JSON and
// reveal server paths. They still go to the PHP error log.
ini_set('display_errors', '0');

require_once __DIR__ . '/../config/database.php';

const PRODUCT_CATEGORIES = ['Laptop', 'Parts', 'Accessories'];

const PRICE_MIN = 0.01;
const PRICE_MAX = 1000000;
const STOCK_MAX = 100000;

/**
 * Sends CORS headers so the API can also be called from Flutter web,
 * and answers preflight requests immediately.
 */
function send_cors_headers(): void
{
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Accept, X-HTTP-Method-Override');

    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}

/**
 * Writes a JSON response and stops the script.
 */
function send_json(int $status, array $payload): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(
        $payload,
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE
    );
    exit;
}

/**
 * Reads a query-string parameter as a trimmed string. Arrays such as
 * ?search[]=x are treated as empty instead of triggering a warning.
 */
function query_string(string $key): string
{
    $value = $_GET[$key] ?? '';

    return is_string($value) ? trim($value) : '';
}

function send_error(int $status, string $message, array $errors = []): never
{
    $payload = ['success' => false, 'message' => $message];
    if ($errors) {
        $payload['errors'] = $errors;
    }
    send_json($status, $payload);
}

/**
 * Decodes the request body. JSON is the primary format, but form-encoded
 * bodies are accepted too so the API works with HTML forms or Postman.
 */
function read_request_body(): array
{
    $contentType = $_SERVER['CONTENT_TYPE'] ?? '';

    if (stripos($contentType, 'multipart/form-data') !== false) {
        // PHP only parses multipart bodies for real POST requests.
        if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
            send_error(415, 'multipart/form-data only works with POST. Send PUT/DELETE as JSON or x-www-form-urlencoded, or POST with _method=PUT.');
        }
        return $_POST;
    }

    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }

    if (stripos($contentType, 'application/x-www-form-urlencoded') !== false) {
        parse_str($raw, $form);
        return $form;
    }

    $data = json_decode($raw, true);
    if (!is_array($data)) {
        send_error(400, 'Request body must be a valid JSON object.');
    }

    return $data;
}

/**
 * Resolves the effective HTTP method. Clients that cannot send PUT or DELETE
 * may POST with an "X-HTTP-Method-Override" header or a "_method" field.
 */
function resolve_method(array $body): string
{
    $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

    if ($method === 'POST') {
        $override = $_SERVER['HTTP_X_HTTP_METHOD_OVERRIDE'] ?? ($body['_method'] ?? null);
        if (is_string($override) && in_array(strtoupper($override), ['PUT', 'DELETE'], true)) {
            return strtoupper($override);
        }
    }

    return $method;
}

/**
 * Reads the "id" query parameter as a positive integer, or null when absent.
 */
function read_id(): ?int
{
    if (!isset($_GET['id']) || $_GET['id'] === '') {
        return null;
    }

    $id = filter_var($_GET['id'], FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
    if ($id === false) {
        send_error(400, 'The "id" parameter must be a positive integer.');
    }

    return $id;
}

function clean_string(mixed $value): string
{
    if (is_string($value)) {
        return trim($value);
    }
    if (is_int($value) || is_float($value)) {
        return (string) $value;
    }
    return '';
}

function string_length(string $value): int
{
    return function_exists('mb_strlen') ? mb_strlen($value) : strlen($value);
}

/**
 * Parses a price sent as a JSON number or a numeric string such as "49.99".
 * Returns null unless it is between 0.01 and 1,000,000 with at most two
 * decimals. Booleans, arrays and text like "1e3" or "12.345" are rejected.
 */
function parse_price(mixed $value): ?float
{
    if (is_int($value) || is_float($value)) {
        $price = (float) $value;
        // Floats cannot store 0.1 exactly, so compare with a tiny tolerance.
        if (!is_finite($price) || abs(round($price, 2) - $price) >= 1e-9) {
            return null;
        }
    } elseif (is_string($value) && preg_match('/^\d+(\.\d{1,2})?$/', trim($value)) === 1) {
        $price = (float) trim($value);
    } else {
        return null;
    }

    $price = round($price, 2);

    return ($price >= PRICE_MIN && $price <= PRICE_MAX) ? $price : null;
}

/**
 * Validates and normalises a product payload.
 *
 * @return array{0: array, 1: array} [cleanData, errors]
 */
function validate_product(array $input): array
{
    $errors = [];

    $name = clean_string($input['name'] ?? '');
    if ($name === '') {
        $errors['name'] = 'Name is required.';
    } elseif (string_length($name) < 2 || string_length($name) > 120) {
        $errors['name'] = 'Name must be between 2 and 120 characters.';
    }

    $category = clean_string($input['category'] ?? '');
    if ($category === '') {
        $errors['category'] = 'Category is required.';
    } elseif (!in_array($category, PRODUCT_CATEGORIES, true)) {
        $errors['category'] = 'Category must be one of: ' . implode(', ', PRODUCT_CATEGORIES) . '.';
    }

    $brand = clean_string($input['brand'] ?? '');
    if (string_length($brand) > 60) {
        $errors['brand'] = 'Brand must be at most 60 characters.';
    }

    $price = parse_price($input['price'] ?? null);
    if ($price === null) {
        $errors['price'] = 'Price must be a number from 0.01 to 1,000,000 with at most 2 decimals.';
    }

    $rawStock = $input['stock'] ?? null;
    $stock = is_bool($rawStock) ? false : filter_var($rawStock, FILTER_VALIDATE_INT, ['options' => ['min_range' => 0, 'max_range' => STOCK_MAX]]);
    if ($stock === false) {
        $errors['stock'] = 'Stock must be a whole number from 0 to 100,000.';
    }

    $description = clean_string($input['description'] ?? '');
    if (string_length($description) > 2000) {
        $errors['description'] = 'Description must be at most 2000 characters.';
    }

    $imageUrl = clean_string($input['image_url'] ?? '');
    if ($imageUrl !== '') {
        $scheme = strtolower((string) parse_url($imageUrl, PHP_URL_SCHEME));
        if (strlen($imageUrl) > 500
            || preg_match('/[^!-~]/', $imageUrl) === 1 // printable ASCII only: no spaces or accents
            || filter_var($imageUrl, FILTER_VALIDATE_URL) === false
            || !in_array($scheme, ['http', 'https'], true)) {
            $errors['image_url'] = 'Image URL must be a valid http(s) link of at most 500 characters.';
        }
    }

    // Optional link to a product on dummyjson.com. Empty means "not linked".
    // The upper bound keeps the value inside a signed 32-bit INT column.
    $rawDummy = $input['dummyjson_id'] ?? null;
    $dummyId = null;
    if ($rawDummy !== null && !(is_string($rawDummy) && trim($rawDummy) === '')) {
        $dummyId = is_bool($rawDummy) ? false : filter_var($rawDummy, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 2147483647]]);
        if ($dummyId === false) {
            $errors['dummyjson_id'] = 'DummyJSON id must be a positive whole number.';
            $dummyId = null;
        }
    }

    $clean = [
        'name' => $name,
        'category' => $category,
        'brand' => $brand,
        // DECIMAL(10,2) column: bind as an exact string, e.g. "1999.99".
        'price' => $price === null ? null : number_format($price, 2, '.', ''),
        'stock' => $stock === false ? null : $stock,
        'description' => $description,
        'image_url' => $imageUrl === '' ? null : $imageUrl,
        'dummyjson_id' => $dummyId,
    ];

    return [$clean, $errors];
}

/**
 * Casts a database row to the JSON shape the app expects.
 */
function format_product(array $row): array
{
    return [
        'id' => (int) $row['id'],
        'name' => $row['name'],
        'category' => $row['category'],
        'brand' => $row['brand'],
        'price' => round((float) $row['price'], 2),
        'stock' => (int) $row['stock'],
        'description' => $row['description'],
        'image_url' => $row['image_url'],
        'dummyjson_id' => $row['dummyjson_id'] === null ? null : (int) $row['dummyjson_id'],
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
    ];
}

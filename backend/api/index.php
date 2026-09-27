<?php
/**
 * Health check: GET api/ (or api/index.php)
 * Used by the app's Server Settings screen to test the connection.
 */

require_once __DIR__ . '/helpers.php';

send_cors_headers();

try {
    $count = (int) db()->query('SELECT COUNT(*) FROM products')->fetchColumn();
} catch (PDOException $e) {
    error_log('[techstore-api] ' . $e->getMessage());
    send_error(500, 'API is running but the database is unavailable. Start MySQL and import database/schema.sql.');
}

send_json(200, [
    'success' => true,
    'message' => 'TechStore API is running.',
    'product_count' => $count,
    'endpoints' => [
        'GET products.php',
        'GET products.php?id={id}',
        'POST products.php',
        'PUT products.php?id={id}',
        'DELETE products.php?id={id}',
    ],
]);

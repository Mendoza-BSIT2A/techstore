<?php
/**
 * TechStore REST API - full CRUD on the `products` table.
 *
 *   GET    products.php                 List products (optional: search, category, sort)
 *   GET    products.php?id={id}         Get one product
 *   POST   products.php                 Create a product (JSON body)
 *   PUT    products.php?id={id}         Update a product (JSON body)
 *   DELETE products.php?id={id}         Delete a product
 *
 * sort = name (default) | newest | oldest | price_asc | price_desc
 *
 * Clients that cannot send PUT/DELETE may POST with the header
 * "X-HTTP-Method-Override: PUT|DELETE" or a "_method" body field.
 */

require_once __DIR__ . '/helpers.php';

send_cors_headers();

try {
    $requestMethod = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
    $body = in_array($requestMethod, ['POST', 'PUT', 'DELETE'], true) ? read_request_body() : [];
    $method = resolve_method($body);
    $id = read_id();

    if ($id === null && in_array($method, ['PUT', 'DELETE'], true) && isset($body['id'])
        && (is_int($body['id']) || is_string($body['id']))) {
        $_GET['id'] = (string) $body['id'];
        $id = read_id();
    }

    match ($method) {
        'GET' => $id === null ? list_products() : show_product($id),
        'POST' => create_product($body),
        'PUT' => update_product(require_id($id, 'update'), $body),
        'DELETE' => delete_product(require_id($id, 'delete')),
        default => method_not_allowed($method),
    };
} catch (PDOException $e) {
    error_log('[techstore-api] ' . $e->getMessage());
    send_error(500, 'Database error. Make sure MySQL is running and database/schema.sql has been imported.');
} catch (Throwable $e) {
    error_log('[techstore-api] ' . $e->getMessage());
    send_error(500, 'Unexpected server error.');
}

function require_id(?int $id, string $action): int
{
    if ($id === null) {
        send_error(400, "An \"id\" query parameter is required to {$action} a product.");
    }

    return $id;
}

function method_not_allowed(string $method): never
{
    header('Allow: GET, POST, PUT, DELETE, OPTIONS');
    send_error(405, "Method {$method} is not allowed.");
}

function find_product(int $id): ?array
{
    $stmt = db()->prepare('SELECT * FROM products WHERE id = :id');
    $stmt->execute([':id' => $id]);
    $row = $stmt->fetch();

    return $row === false ? null : $row;
}

function find_product_or_404(int $id): array
{
    $row = find_product($id);
    if ($row === null) {
        send_error(404, "Product with id {$id} was not found.");
    }

    return $row;
}

/**
 * The utf8mb4_unicode_ci collation makes this comparison case-insensitive,
 * so "dell xps 13 9300" clashes with "Dell XPS 13 9300".
 */
function name_is_taken(string $name, ?int $exceptId = null): bool
{
    $sql = 'SELECT COUNT(*) FROM products WHERE name = :name';
    $params = [':name' => $name];

    if ($exceptId !== null) {
        $sql .= ' AND id <> :id';
        $params[':id'] = $exceptId;
    }

    $stmt = db()->prepare($sql);
    $stmt->execute($params);

    return (int) $stmt->fetchColumn() > 0;
}

function list_products(): never
{
    $where = [];
    $params = [];

    $search = query_string('search');
    if ($search !== '') {
        $like = '%' . addcslashes($search, '%_\\') . '%';
        $where[] = '(name LIKE :q1 OR brand LIKE :q2 OR description LIKE :q3)';
        $params[':q1'] = $like;
        $params[':q2'] = $like;
        $params[':q3'] = $like;
    }

    $category = query_string('category');
    if ($category !== '') {
        $where[] = 'category = :category';
        $params[':category'] = $category;
    }

    $orderBy = match (query_string('sort')) {
        'newest' => 'created_at DESC, id DESC',
        'oldest' => 'created_at ASC, id ASC',
        'price_asc' => 'price ASC, name ASC',
        'price_desc' => 'price DESC, name ASC',
        default => 'name ASC',
    };

    $sql = 'SELECT * FROM products'
        . ($where ? ' WHERE ' . implode(' AND ', $where) : '')
        . " ORDER BY {$orderBy}";

    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    $products = array_map('format_product', $stmt->fetchAll());

    send_json(200, [
        'success' => true,
        'count' => count($products),
        'data' => $products,
    ]);
}

function show_product(int $id): never
{
    send_json(200, [
        'success' => true,
        'data' => format_product(find_product_or_404($id)),
    ]);
}

function create_product(array $body): never
{
    [$data, $errors] = validate_product($body);

    if (!isset($errors['name']) && name_is_taken($data['name'])) {
        $errors['name'] = 'A product with this name already exists.';
    }
    if ($errors) {
        send_error(422, 'Please fix the highlighted fields.', $errors);
    }

    try {
        $stmt = db()->prepare(
            'INSERT INTO products
                (name, category, brand, price, stock, description, image_url, dummyjson_id)
             VALUES
                (:name, :category, :brand, :price, :stock, :description, :image_url, :dummyjson_id)'
        );
        $stmt->execute(prefix_keys($data));
    } catch (PDOException $e) {
        handle_duplicate_name($e);
    }

    $id = (int) db()->lastInsertId();
    header('Location: products.php?id=' . $id);

    send_json(201, [
        'success' => true,
        'message' => 'Product created.',
        'data' => format_product(find_product_or_404($id)),
    ]);
}

function update_product(int $id, array $body): never
{
    find_product_or_404($id);

    [$data, $errors] = validate_product($body);

    if (!isset($errors['name']) && name_is_taken($data['name'], $id)) {
        $errors['name'] = 'A product with this name already exists.';
    }
    if ($errors) {
        send_error(422, 'Please fix the highlighted fields.', $errors);
    }

    // updated_at is set explicitly so every successful PUT bumps it, even
    // when nothing changed (same behaviour as the Supabase trigger).
    try {
        $stmt = db()->prepare(
            'UPDATE products SET
                name = :name,
                category = :category,
                brand = :brand,
                price = :price,
                stock = :stock,
                description = :description,
                image_url = :image_url,
                dummyjson_id = :dummyjson_id,
                updated_at = CURRENT_TIMESTAMP
             WHERE id = :id'
        );
        $stmt->execute(prefix_keys($data) + [':id' => $id]);
    } catch (PDOException $e) {
        handle_duplicate_name($e);
    }

    send_json(200, [
        'success' => true,
        'message' => 'Product updated.',
        'data' => format_product(find_product_or_404($id)),
    ]);
}

function delete_product(int $id): never
{
    $row = find_product_or_404($id);

    $stmt = db()->prepare('DELETE FROM products WHERE id = :id');
    $stmt->execute([':id' => $id]);

    send_json(200, [
        'success' => true,
        'message' => "Product \"{$row['name']}\" deleted.",
        'data' => format_product($row),
    ]);
}

/**
 * Turns ['name' => ...] into [':name' => ...] for PDO.
 */
function prefix_keys(array $data): array
{
    $params = [];
    foreach ($data as $key => $value) {
        $params[':' . $key] = $value;
    }

    return $params;
}

/**
 * The unique index on `name` is the last line of defence against a race
 * between the name check and the write. 1062 is MySQL's "duplicate entry".
 */
function handle_duplicate_name(PDOException $e): never
{
    if ($e->getCode() === '23000' && (int) ($e->errorInfo[1] ?? 0) === 1062) {
        send_error(422, 'Please fix the highlighted fields.', [
            'name' => 'A product with this name already exists.',
        ]);
    }

    throw $e;
}

/**
 * TechStore REST API - Supabase Edge Function.
 *
 * The online twin of backend/api/products.php: same endpoints, JSON, status
 * codes and validation, so the Flutter app works with either backend.
 *
 *   GET    /store-api/products.php                 List products (optional: search, category, sort)
 *   GET    /store-api/products.php?id={id}         Get one product
 *   POST   /store-api/products.php                 Create a product (JSON body)
 *   PUT    /store-api/products.php?id={id}         Update a product (JSON body)
 *   DELETE /store-api/products.php?id={id}         Delete a product
 *   GET    /store-api/                             Health check
 *
 * "/products" (without .php) works too. Clients that cannot send PUT/DELETE may
 * POST with "X-HTTP-Method-Override: PUT|DELETE" or a "_method" body field.
 *
 * Deploy:  npx supabase functions deploy store-api --project-ref <ref> --no-verify-jwt --use-api
 * URL:     https://<ref>.supabase.co/functions/v1/store-api
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

const CATEGORIES = ['Laptop', 'Parts', 'Accessories'];

const MAX_PRICE = 1_000_000;
const MAX_STOCK = 100_000;
// Largest value a Postgres "integer" column can hold.
const MAX_DUMMYJSON_ID = 2_147_483_647;

// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided to every Edge Function
// automatically. The service role bypasses RLS, so only this API can touch the table.
const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'Content-Type, Accept, X-HTTP-Method-Override, Authorization, apikey, x-client-info',
};

type Body = Record<string, unknown>;
type Product = Record<string, unknown>;

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly errors?: Record<string, string>,
  ) {
    super(message);
  }
}

function sendJson(status: number, payload: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json; charset=utf-8', ...headers },
  });
}

function validationError(errors: Record<string, string>): HttpError {
  return new HttpError(422, 'Please fix the highlighted fields.', errors);
}

// ---------------------------------------------------------------------------
// Request helpers
// ---------------------------------------------------------------------------

async function readRequestBody(req: Request): Promise<Body> {
  const contentType = req.headers.get('content-type') ?? '';
  const raw = await req.text();
  if (raw.trim() === '') return {};

  if (contentType.includes('application/x-www-form-urlencoded')) {
    return Object.fromEntries(new URLSearchParams(raw));
  }
  if (contentType.includes('multipart/form-data')) {
    const form = await new Request(req.url, {
      method: 'POST',
      headers: { 'content-type': contentType },
      body: raw,
    }).formData();
    return Object.fromEntries([...form.entries()].map(([k, v]) => [k, String(v)]));
  }

  try {
    const data = JSON.parse(raw);
    if (data !== null && typeof data === 'object' && !Array.isArray(data)) return data as Body;
  } catch {
    // fall through
  }
  throw new HttpError(400, 'Request body must be a valid JSON object.');
}

function resolveMethod(req: Request, body: Body): string {
  const method = req.method.toUpperCase();
  if (method === 'POST') {
    const override = req.headers.get('x-http-method-override') ?? body._method;
    if (typeof override === 'string' && ['PUT', 'DELETE'].includes(override.toUpperCase())) {
      return override.toUpperCase();
    }
  }
  return method;
}

function parseId(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string' && typeof value !== 'number') {
    throw new HttpError(400, 'The "id" parameter must be a positive integer.');
  }
  const text = String(value).trim();
  if (!/^\d+$/.test(text) || Number(text) < 1 || !Number.isSafeInteger(Number(text))) {
    throw new HttpError(400, 'The "id" parameter must be a positive integer.');
  }
  return Number(text);
}

function requireId(id: number | null, action: string): number {
  if (id === null) {
    throw new HttpError(400, `An "id" query parameter is required to ${action} a product.`);
  }
  return id;
}

// ---------------------------------------------------------------------------
// Validation (mirrors validate_product() in backend/api/helpers.php)
// ---------------------------------------------------------------------------

function cleanString(value: unknown): string {
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return '';
}

/** Length in code points, like PHP's mb_strlen(). */
function length(value: string): number {
  return [...value].length;
}

/** Text form of a number or numeric string; booleans and other types give ''. */
function numberText(value: unknown): string {
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : '';
  if (typeof value === 'string') return value.trim();
  return '';
}

/** A whole number from min to max (number or digit string), or null. */
function wholeNumber(value: unknown, min: number, max: number): number | null {
  const text = numberText(value);
  if (!/^\d+$/.test(text)) return null;
  const n = Number(text);
  return n >= min && n <= max ? n : null;
}

/**
 * A price from 0.01 to 1,000,000 with at most 2 decimals, or null (mirrors
 * parse_price() in helpers.php). Accepts a JSON number or a numeric string
 * such as "49.99"; booleans and text like "1e3" or "12.345" are rejected.
 */
function parsePrice(value: unknown): number | null {
  let price: number;
  if (typeof value === 'number') {
    // Floats cannot store 0.1 exactly, so compare with a tiny tolerance.
    if (!Number.isFinite(value) || Math.abs(Math.round(value * 100) / 100 - value) >= 1e-9) {
      return null;
    }
    price = value;
  } else if (typeof value === 'string' && /^\d+(\.\d{1,2})?$/.test(value.trim())) {
    price = Number(value.trim());
  } else {
    return null;
  }

  price = Math.round(price * 100) / 100;
  return price >= 0.01 && price <= MAX_PRICE ? price : null;
}

function isBlank(value: unknown): boolean {
  return value === null || value === undefined || (typeof value === 'string' && value.trim() === '');
}

function isValidImageUrl(value: string): boolean {
  if (value.length > 500 || /[^\x21-\x7E]/.test(value) || !/^https?:\/\//i.test(value)) {
    return false;
  }
  try {
    const url = new URL(value);
    return (url.protocol === 'http:' || url.protocol === 'https:') && url.hostname !== '';
  } catch {
    return false;
  }
}

/** Returns [cleanData, errors], like validate_product() in helpers.php. */
function validateProduct(input: Body): [Product, Record<string, string>] {
  const errors: Record<string, string> = {};

  const name = cleanString(input.name);
  if (name === '') {
    errors.name = 'Name is required.';
  } else if (length(name) < 2 || length(name) > 120) {
    errors.name = 'Name must be between 2 and 120 characters.';
  }

  const category = cleanString(input.category);
  if (category === '') {
    errors.category = 'Category is required.';
  } else if (!CATEGORIES.includes(category)) {
    errors.category = `Category must be one of: ${CATEGORIES.join(', ')}.`;
  }

  const brand = cleanString(input.brand);
  if (length(brand) > 60) errors.brand = 'Brand must be at most 60 characters.';

  const price = parsePrice(input.price);
  if (price === null) {
    errors.price = 'Price must be a number from 0.01 to 1,000,000 with at most 2 decimals.';
  }

  const stock = wholeNumber(input.stock, 0, MAX_STOCK);
  if (stock === null) {
    errors.stock = 'Stock must be a whole number from 0 to 100,000.';
  }

  const description = cleanString(input.description);
  if (length(description) > 2000) {
    errors.description = 'Description must be at most 2000 characters.';
  }

  const imageUrl = cleanString(input.image_url);
  if (imageUrl !== '' && !isValidImageUrl(imageUrl)) {
    errors.image_url = 'Image URL must be a valid http(s) link of at most 500 characters.';
  }

  const hasDummyId = !isBlank(input.dummyjson_id);
  const dummyId = hasDummyId ? wholeNumber(input.dummyjson_id, 1, MAX_DUMMYJSON_ID) : null;
  if (hasDummyId && dummyId === null) {
    errors.dummyjson_id = 'DummyJSON id must be a positive whole number.';
  }

  const clean = {
    name,
    category,
    brand,
    price,
    stock,
    description,
    image_url: imageUrl === '' ? null : imageUrl,
    dummyjson_id: dummyId,
  };
  return [clean, errors];
}

// ---------------------------------------------------------------------------
// Database access
// ---------------------------------------------------------------------------

/** Escapes LIKE wildcards so user input is matched literally. */
function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (c) => `\\${c}`);
}

/** Quotes a value for a PostgREST or() filter. */
function quoteFilterValue(value: string): string {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

/** Case-insensitive "contains", used to re-check PostgREST LIKE results. */
function containsText(value: unknown, needle: string): boolean {
  return typeof value === 'string' && value.toLowerCase().includes(needle.toLowerCase());
}

function checkDb(error: { code?: string; message: string } | null): void {
  if (error) throw error;
}

async function findProduct(id: number): Promise<Product> {
  const { data, error } = await db.from('products').select('*').eq('id', id).maybeSingle();
  checkDb(error);
  if (!data) throw new HttpError(404, `Product with id ${id} was not found.`);
  return data;
}

async function nameIsTaken(name: string, exceptId?: number): Promise<boolean> {
  let query = db.from('products').select('id, name').ilike('name', escapeLike(name));
  if (exceptId !== undefined) query = query.neq('id', exceptId);
  const { data, error } = await query;
  checkDb(error);
  // PostgREST reads "*" in a LIKE pattern as a wildcard, so compare exactly here.
  const key = name.toLowerCase();
  return (data ?? []).some((row: Product) => String(row.name).toLowerCase() === key);
}

function duplicateNameOr(error: { code?: string; message: string }): never {
  if (error.code === '23505') {
    throw validationError({ name: 'A product with this name already exists.' });
  }
  throw error;
}

/**
 * Adds the duplicate-name error, then answers 422 if any field failed. Like the
 * PHP API, a taken name is reported together with the other field errors.
 */
async function assertValid(
  data: Product,
  errors: Record<string, string>,
  exceptId?: number,
): Promise<void> {
  if (!errors.name && await nameIsTaken(data.name as string, exceptId)) {
    errors.name = 'A product with this name already exists.';
  }
  if (Object.keys(errors).length > 0) throw validationError(errors);
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async function health(): Promise<Response> {
  const { count, error } = await db.from('products').select('*', { count: 'exact', head: true });
  if (error) {
    console.error(error);
    throw new HttpError(
      500,
      'API is running but the database is unavailable. Run supabase/schema.sql in the SQL Editor.',
    );
  }
  return sendJson(200, {
    success: true,
    message: 'TechStore API is running.',
    product_count: count ?? 0,
    endpoints: [
      'GET products.php',
      'GET products.php?id={id}',
      'POST products.php',
      'PUT products.php?id={id}',
      'DELETE products.php?id={id}',
    ],
  });
}

async function listProducts(params: URLSearchParams): Promise<Response> {
  let query = db.from('products').select('*');

  const search = (params.get('search') ?? '').trim();
  if (search !== '') {
    const pattern = quoteFilterValue(`%${escapeLike(search)}%`);
    query = query.or(`name.ilike.${pattern},brand.ilike.${pattern},description.ilike.${pattern}`);
  }

  const category = (params.get('category') ?? '').trim();
  if (category !== '') query = query.eq('category', category);

  switch (params.get('sort')) {
    case 'newest':
      query = query.order('created_at', { ascending: false }).order('id', { ascending: false });
      break;
    case 'oldest':
      query = query.order('created_at', { ascending: true }).order('id', { ascending: true });
      break;
    // Equal prices fall back to name, like the PHP API; id keeps the order stable.
    case 'price_asc':
      query = query.order('price', { ascending: true }).order('name').order('id');
      break;
    case 'price_desc':
      query = query.order('price', { ascending: false }).order('name').order('id');
      break;
    default:
      query = query.order('name', { ascending: true }).order('id', { ascending: true });
  }

  const { data, error } = await query;
  checkDb(error);
  let products: Product[] = data ?? [];

  // PostgREST reads "*" in a LIKE pattern as a wildcard; keep literal matches only.
  if (search.includes('*')) {
    products = products.filter((p) =>
      containsText(p.name, search) || containsText(p.brand, search) ||
      containsText(p.description, search)
    );
  }

  return sendJson(200, { success: true, count: products.length, data: products });
}

async function showProduct(id: number): Promise<Response> {
  return sendJson(200, { success: true, data: await findProduct(id) });
}

async function createProduct(body: Body): Promise<Response> {
  const [data, errors] = validateProduct(body);
  await assertValid(data, errors);

  const { data: created, error } = await db.from('products').insert(data).select().single();
  if (error) duplicateNameOr(error);

  return sendJson(
    201,
    { success: true, message: 'Product created.', data: created },
    { Location: `products.php?id=${created.id}` },
  );
}

async function updateProduct(id: number, body: Body): Promise<Response> {
  await findProduct(id);
  const [data, errors] = validateProduct(body);
  await assertValid(data, errors, id);

  const { data: updated, error } = await db
    .from('products')
    .update(data)
    .eq('id', id)
    .select()
    .single();
  if (error) duplicateNameOr(error);

  return sendJson(200, { success: true, message: 'Product updated.', data: updated });
}

async function deleteProduct(id: number): Promise<Response> {
  const product = await findProduct(id);
  const { error } = await db.from('products').delete().eq('id', id);
  checkDb(error);
  return sendJson(200, {
    success: true,
    message: `Product "${product.name}" deleted.`,
    data: product,
  });
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const url = new URL(req.url);
    // Path is "/store-api/<endpoint>" (the first segment is the function name).
    const parts = url.pathname.split('/').filter(Boolean);
    const endpoint = parts.length > 1 ? parts[parts.length - 1] : '';

    if (['', 'store-api', 'index.php'].includes(endpoint)) {
      if (req.method !== 'GET') throw new HttpError(405, `Method ${req.method} is not allowed.`);
      return await health();
    }
    if (endpoint !== 'products' && endpoint !== 'products.php') {
      throw new HttpError(404, `Unknown endpoint "${endpoint}". Use products.php.`);
    }

    const body = ['POST', 'PUT', 'DELETE'].includes(req.method) ? await readRequestBody(req) : {};
    const method = resolveMethod(req, body);

    let id = parseId(url.searchParams.get('id'));
    if (id === null && (method === 'PUT' || method === 'DELETE')) {
      id = parseId(typeof body.id === 'boolean' ? undefined : body.id);
    }

    switch (method) {
      case 'GET':
        return id === null ? await listProducts(url.searchParams) : await showProduct(id);
      case 'POST':
        return await createProduct(body);
      case 'PUT':
        return await updateProduct(requireId(id, 'update'), body);
      case 'DELETE':
        return await deleteProduct(requireId(id, 'delete'));
      default:
        return sendJson(
          405,
          { success: false, message: `Method ${method} is not allowed.` },
          { Allow: 'GET, POST, PUT, DELETE, OPTIONS' },
        );
    }
  } catch (e) {
    if (e instanceof HttpError) {
      return sendJson(e.status, {
        success: false,
        message: e.message,
        ...(e.errors ? { errors: e.errors } : {}),
      });
    }
    console.error(e);
    return sendJson(500, {
      success: false,
      message: 'Database error. Make sure supabase/schema.sql was run in the SQL Editor.',
    });
  }
});

-- TechStore Hub database
-- Import with phpMyAdmin (Import tab), or from the project folder in cmd.exe:
--   C:\xampp\mysql\bin\mysql.exe -u root < backend\database\schema.sql
-- (PowerShell: cmd /c "C:\xampp\mysql\bin\mysql.exe -u root < backend\database\schema.sql")
-- WARNING: re-importing drops and recreates the `products` table.

CREATE DATABASE IF NOT EXISTS techstore_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE techstore_db;

DROP TABLE IF EXISTS products;

-- The _ci collation makes the UNIQUE name index case-insensitive.
CREATE TABLE products (
    id            INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    name          VARCHAR(120)   NOT NULL,
    category      VARCHAR(20)    NOT NULL COMMENT 'Laptop, Parts or Accessories',
    brand         VARCHAR(60)    NOT NULL DEFAULT '',
    price         DECIMAL(10,2)  NOT NULL COMMENT 'USD, 0.01 to 1,000,000',
    stock         INT UNSIGNED   NOT NULL COMMENT '0 to 100,000; 1-5 is low stock',
    description   TEXT           NOT NULL,
    image_url     VARCHAR(500)   NULL,
    dummyjson_id  INT UNSIGNED   NULL COMMENT 'Linked product id on dummyjson.com, e.g. 78',
    created_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_products_name (name),
    KEY idx_products_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO products
    (name, category, brand, price, stock, dummyjson_id, image_url, description)
VALUES
    ('Apple MacBook Pro 14 Inch Space Grey', 'Laptop', 'Apple', 1999.99, 24, 78,
     'https://cdn.dummyjson.com/product-images/laptops/apple-macbook-pro-14-inch-space-grey/thumbnail.webp',
     'Apple M1 Pro chip, 14-inch Liquid Retina XDR display and all-day battery life.'),
    ('Asus Zenbook Pro Dual Screen Laptop', 'Laptop', 'Asus', 1799.99, 45, 79,
     'https://cdn.dummyjson.com/product-images/laptops/asus-zenbook-pro-dual-screen-laptop/thumbnail.webp',
     'Creator laptop with a second touchscreen above the keyboard for multitasking.'),
    ('Huawei Matebook X Pro', 'Laptop', 'Huawei', 1399.99, 75, 80,
     'https://cdn.dummyjson.com/product-images/laptops/huawei-matebook-x-pro/thumbnail.webp',
     'Thin and light ultrabook with a 3K touchscreen and a pop-up webcam.'),
    ('Lenovo Yoga 920', 'Laptop', 'Lenovo', 1099.99, 40, 81,
     'https://cdn.dummyjson.com/product-images/laptops/lenovo-yoga-920/thumbnail.webp',
     '2-in-1 convertible with a 360-degree hinge and pen support.'),
    ('Dell XPS 13 9300', 'Laptop', 'Dell', 1499.99, 74, 82,
     'https://cdn.dummyjson.com/product-images/laptops/new-dell-xps-13-9300-laptop/thumbnail.webp',
     'Compact 13.4-inch laptop with an InfinityEdge display and 11th-gen Intel CPU.'),
    ('Apple Airpods', 'Accessories', 'Apple', 129.99, 67, 100,
     'https://cdn.dummyjson.com/product-images/mobile-accessories/apple-airpods/thumbnail.webp',
     'Wireless earbuds with automatic pairing and a charging case.'),
    ('Apple Airpower Wireless Charger', 'Accessories', 'Apple', 79.99, 1, 102,
     'https://cdn.dummyjson.com/product-images/mobile-accessories/apple-airpower-wireless-charger/thumbnail.webp',
     'Wireless charging pad for phone, watch and earbuds at the same time.'),
    ('Beats Flex Wireless Earphones', 'Accessories', 'Beats', 49.99, 50, 107,
     'https://cdn.dummyjson.com/product-images/mobile-accessories/beats-flex-wireless-earphones/thumbnail.webp',
     'Everyday Bluetooth earphones with magnetic earbuds and 12-hour battery.'),
    ('Apple MagSafe Battery Pack', 'Accessories', 'Apple', 99.99, 0, 105,
     'https://cdn.dummyjson.com/product-images/mobile-accessories/apple-magsafe-battery-pack/thumbnail.webp',
     'Snap-on MagSafe battery that tops up your iPhone on the go.'),
    ('Kingston FURY Beast 16GB DDR4-3200 RAM', 'Parts', 'Kingston', 49.99, 35, NULL, NULL,
     '16GB DDR4 desktop memory module running at 3200 MT/s with a low-profile heat spreader.'),
    ('Samsung 980 PRO 1TB NVMe SSD', 'Parts', 'Samsung', 89.99, 18, NULL, NULL,
     'PCIe 4.0 M.2 solid-state drive with up to 7,000 MB/s read speed.'),
    ('NVIDIA GeForce RTX 4060 8GB Graphics Card', 'Parts', 'NVIDIA', 299.99, 4, NULL, NULL,
     '1080p gaming graphics card with DLSS 3 and 8GB GDDR6 memory.');

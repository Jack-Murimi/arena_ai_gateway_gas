-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0004
-- Real product catalogue (replaces placeholder seed products)
--
-- Brands: Afrigas, K-Gas, Total, Ola (Oilibya), Progas, Lake Gas, Tosha,
-- Supa Gas (National Oil), Jatel, Hashi, etc. Regulators & burners are
-- Kabsons only.
--
-- NOTE: prices below are PLACEHOLDERS — set the real ones from the app
-- (Inventory → product → edit) once you review. Buying cost is updated
-- by purchases; selling price is changeable at the POS (flagged for
-- admin/director approval).
-- ============================================================================

-- Replace all placeholder seeds with the real catalogue.
-- Safe to delete: no sales/stock/purchases exist yet.
delete from public.products;

insert into public.products
  (name, product_type, size_kg, brand, sale_price, cost_price, low_stock_threshold)
values
  -- -------------------- 13kg refills --------------------
  ('Afrigas 13kg',    'refill', 13,    'Afrigas',        2000, 1700, 10),
  ('Alfa 13kg',       'refill', 13,    'Alfa',           2000, 1700, 10),
  ('Amaan 13kg',      'refill', 13,    'Amaan',          2000, 1700, 10),
  ('Eda 13kg',        'refill', 13,    'Eda',            2000, 1700, 10),
  ('Gaskey 13kg',     'refill', 13,    'Gaskey',         2000, 1700, 10),
  ('Hashi 13kg',      'refill', 13,    'Hashi',          2000, 1700, 10),
  ('Hass 13kg',       'refill', 13,    'Hass',           2000, 1700, 10),
  ('Hunker 13kg',     'refill', 13,    'Hunker',         2000, 1700, 10),
  ('Jamii 13kg',      'refill', 13,    'Jamii',          2000, 1700, 10),
  ('Jamil 13kg',      'refill', 13,    'Jamil',          2000, 1700, 10),
  ('Jatel 13kg',      'refill', 13,    'Jatel',          2000, 1700, 10),
  ('K-Gas 13kg',      'refill', 13,    'K-Gas',          2000, 1700, 10),
  ('Lake Gas 13kg',   'refill', 13,    'Lake Gas',       2000, 1700, 10),
  ('Mengas 13kg',     'refill', 13,    'Mengas',         2000, 1700, 10),
  ('Midgas 13kg',     'refill', 13,    'Midgas',         2000, 1700, 10),
  ('Ola 13kg',        'refill', 13,    'Ola (Oilibya)',  2000, 1700, 10),
  ('Orxy 13kg',       'refill', 13,    'Orxy',           2000, 1700, 10),
  ('Pek 13kg',        'refill', 13,    'Pek',            2000, 1700, 10),
  ('Progas 13kg',     'refill', 13,    'Progas',         2000, 1700, 10),
  ('Raha 13kg',       'refill', 13,    'Raha',           2000, 1700, 10),
  ('Sea Gas 13kg',    'refill', 13,    'Sea Gas',        2000, 1700, 10),
  ('Supa Gas 13kg',   'refill', 13,    'Supa Gas',       2000, 1700, 10),
  ('Tosha 13kg',      'refill', 13,    'Tosha',          2000, 1700, 10),
  ('Total 13kg',      'refill', 13,    'Total',          2000, 1700, 10),
  ('Wanjiku 13kg',    'refill', 13,    'Wanjiku',        2000, 1700, 10),

  -- -------------------- 6kg refills --------------------
  ('Afrigas 6kg',     'refill', 6,     'Afrigas',        1000,  850, 10),
  ('Chinese 6kg',     'refill', 6,     'Chinese',        1000,  850, 10),
  ('City 6kg',        'refill', 6,     'City',           1000,  850, 10),
  ('Eda 6kg',         'refill', 6,     'Eda',            1000,  850, 10),
  ('Hashi 6kg',       'refill', 6,     'Hashi',          1000,  850, 10),
  ('Hunker 6kg',      'refill', 6,     'Hunker',         1000,  850, 10),
  ('K-Gas 6kg',       'refill', 6,     'K-Gas',          1000,  850, 10),
  ('Lake Gas 6kg',    'refill', 6,     'Lake Gas',       1000,  850, 10),
  ('Midgas 6kg',      'refill', 6,     'Midgas',         1000,  850, 10),
  ('Ola 6kg',         'refill', 6,     'Ola (Oilibya)',  1000,  850, 10),
  ('Progas 6kg',      'refill', 6,     'Progas',         1000,  850, 10),
  ('Raha 6kg',        'refill', 6,     'Raha',           1000,  850, 10),
  ('Seagas 6kg',      'refill', 6,     'Seagas',         1000,  850, 10),
  ('Supa Gas 6kg',    'refill', 6,     'Supa Gas',       1000,  850, 10),
  ('Tosha 6kg',       'refill', 6,     'Tosha',          1000,  850, 10),
  ('Total 6kg',       'refill', 6,     'Total',          1000,  850, 10),

  -- -------------------- 22.5kg / 35kg / 45kg refills --------------------
  ('Total 22.5kg',    'refill', 22.5,  'Total',          3400, 2900, 10),
  ('Hashi 35kg',      'refill', 35,    'Hashi',          5200, 4500,  5),
  ('K-Gas 35kg',      'refill', 35,    'K-Gas',          5200, 4500,  5),
  ('Safe Gas 35kg',   'refill', 35,    'Safe Gas',       5200, 4500,  5),
  ('Afrigas 45kg',    'refill', 45,    'Afrigas',        6800, 5900,  5),

  -- -------------------- 50kg refills --------------------
  ('City 50kg',       'refill', 50,    'City',           7300, 6400,  5),
  ('Express 50kg',    'refill', 50,    'Express',        7300, 6400,  5),
  ('Future 50kg',     'refill', 50,    'Future',         7300, 6400,  5),
  ('G-Gas 50kg',      'refill', 50,    'G-Gas',          7300, 6400,  5),
  ('Hashi 50kg',      'refill', 50,    'Hashi',          7300, 6400,  5),
  ('Hunker 50kg',     'refill', 50,    'Hunker',         7300, 6400,  5),
  ('Lake Gas 50kg',   'refill', 50,    'Lake Gas',       7300, 6400,  5),
  ('Midgas 50kg',     'refill', 50,    'Midgas',         7300, 6400,  5),
  ('Ola 50kg',        'refill', 50,    'Ola (Oilibya)',  7300, 6400,  5),
  ('Progas 50kg',     'refill', 50,    'Progas',         7300, 6400,  5),
  ('Raha 50kg',       'refill', 50,    'Raha',           7300, 6400,  5),
  ('Stabex 50kg',     'refill', 50,    'Stabex',         7300, 6400,  5),
  ('Total 50kg',      'refill', 50,    'Total',          7300, 6400,  5),

  -- -------------------- Empty cylinders --------------------
  ('Afrigas Empty 6kg',  'cylinder', 6,  'Afrigas',      2200, 1800,  5),
  ('Afrigas Empty 13kg', 'cylinder', 13, 'Afrigas',      2800, 2300,  5),
  ('Progas Empty 13kg',  'cylinder', 13, 'Progas',       2800, 2300,  5),
  ('City Empty 50kg',    'cylinder', 50, 'City',         4500, 3800,  5),

  -- -------------------- Accessories (Kabsons for regulator/burner) --------------------
  ('Regulator',       'accessory', null, 'Kabsons',       450,  380, 10),
  ('Burner',          'accessory', null, 'Kabsons',       400,  320, 10),
  ('Clips',           'accessory', null, null,            100,   60, 10),
  ('High Pressure Hose','accessory', null, null,          400,  300, 10),
  ('Pipes',           'accessory', null, null,            500,  400, 10),
  ('Grill',           'accessory', null, null,           2500, 2000,  5),
  ('Japeli 500ml',    'accessory', null, 'Japeli',        250,  180, 10),
  ('Japeli 1L',       'accessory', null, 'Japeli',        350,  260, 10),
  ('Japeli 5L',       'accessory', null, 'Japeli',        800,  600, 10),
  ('Japeli 10L',      'accessory', null, 'Japeli',       1200,  900, 10),
  ('Japeli 20L',      'accessory', null, 'Japeli',       2000, 1500,  5),

  -- -------------------- Services --------------------
  ('Aquamist Refill', 'service', null, 'Aquamist',        100,   50,  0),
  ('Keringet Refill', 'service', null, 'Keringet',        100,   50,  0);

-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0005
-- Rename products to the "size brand type" convention:
--   refill    -> "13kg Afrigas refill"
--   cylinder  -> "13kg Afrigas Cylinder"
--   accessory -> "Kabsons regulator" (brand + name)
--   Japeli    -> "5L Japeli" (size first)
-- ============================================================================

-- Helper: 13 -> "13", 22.5 -> "22.5" (no trailing zeros)
-- Refills
update public.products
set name = trim(trailing '.' from trim(trailing '0' from size_kg::text))
           || 'kg ' || brand || ' refill'
where product_type = 'refill' and size_kg is not null and brand is not null;

-- Cylinders
update public.products
set name = trim(trailing '.' from trim(trailing '0' from size_kg::text))
           || 'kg ' || brand || ' Cylinder'
where product_type = 'cylinder' and size_kg is not null and brand is not null;

-- Regulator & Burner (Kabsons only): "Kabsons regulator", "Kabsons burner"
update public.products
set name = 'Kabsons ' || lower(name)
where name in ('Regulator', 'Burner');

-- Japeli water: size first
update public.products
set name = case name
  when 'Japeli 500ml' then '500ml Japeli'
  when 'Japeli 1L'    then '1L Japeli'
  when 'Japeli 5L'    then '5L Japeli'
  when 'Japeli 10L'   then '10L Japeli'
  when 'Japeli 20L'   then '20L Japeli'
  else name
end
where name like 'Japeli %';

-- Services (Aquamist refill, Keringet refill) and unbranded accessories
-- (Clips, Pipes, High Pressure Hose, Grill) keep their names.

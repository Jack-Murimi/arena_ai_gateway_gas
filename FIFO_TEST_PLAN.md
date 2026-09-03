# FIFO Implementation Test Plan

## 🧪 Test Cases

### Test Case 1: Basic FIFO Sale
**Description:** Buy inventory at one price, sell it, verify COGS

**Steps:**
1. Receive 10 units of Product A at KSh 500 each (via admin_receive_order or admin_init_stock)
2. Record a sale of 5 units of Product A at KSh 800 each
3. Verify:
   - Sale total = 5 × 800 = KSh 4,000
   - COGS = 5 × 500 = KSh 2,500
   - Profit = 4,000 - 2,500 = KSh 1,500
   - Margin = (1,500 / 4,000) × 100 = 37.5%

**Expected Result:**
- Receipt shows COGS: KSh 2,500
- Receipt shows Profit: KSh 1,500
- Receipt shows Margin: 37.5%
- Inventory batch shows quantity_remaining = 5

---

### Test Case 2: Multi-Batch FIFO Sale
**Description:** Buy at two different prices, sell more than first batch, verify FIFO

**Steps:**
1. Receive 10 units of Product B at KSh 500 each
2. Receive 5 units of Product B at KSh 550 each
3. Record a sale of 12 units of Product B at KSh 800 each
4. Verify:
   - Sale total = 12 × 800 = KSh 9,600
   - COGS = (10 × 500) + (2 × 550) = 5,000 + 1,100 = KSh 6,100
   - Profit = 9,600 - 6,100 = KSh 3,500
   - Margin = (3,500 / 9,600) × 100 ≈ 36.46%

**Expected Result:**
- First batch: quantity_remaining = 0 (fully consumed)
- Second batch: quantity_remaining = 3 (5 - 2 consumed)
- Receipt shows correct COGS, profit, and margin

---

### Test Case 3: Partial Batch Consumption
**Description:** Sell from middle of a batch

**Steps:**
1. Receive 10 units of Product C at KSh 600 each
2. Record a sale of 3 units of Product C at KSh 900 each
3. Verify:
   - Sale total = 3 × 900 = KSh 2,700
   - COGS = 3 × 600 = KSh 1,800
   - Profit = 2,700 - 1,800 = KSh 900
   - Margin = (900 / 2,700) × 100 ≈ 33.33%
   - Batch shows quantity_remaining = 7

**Expected Result:**
- Batch quantity_remaining = 7
- Receipt shows correct FIFO data

---

### Test Case 4: Service Product (No FIFO)
**Description:** Service products should not create inventory batches or allocations

**Steps:**
1. Create a service product (product_type = 'service')
2. Record a sale of the service product
3. Verify:
   - No inventory batch created
   - No sale_fifo_allocation created
   - Sale recorded successfully
   - COGS = 0 (or not displayed)

**Expected Result:**
- Sale completes without errors
- No FIFO allocations created
- Receipt may show COGS as 0 or hide FIFO section

---

### Test Case 5: Insufficient Stock
**Description:** Try to sell more than available inventory

**Steps:**
1. Receive 5 units of Product D at KSh 400 each
2. Try to record a sale of 10 units of Product D
3. Verify:
   - RPC throws exception with "Insufficient stock" message
   - Flutter catches and displays error to user
   - No sale is recorded
   - Inventory unchanged

**Expected Result:**
- Error message displayed: "Insufficient stock"
- Sale not recorded
- Inventory unchanged

---

### Test Case 6: Multiple Products in One Sale
**Description:** Sale with multiple products, each with different costs

**Steps:**
1. Receive 10 units of Product E at KSh 300 each
2. Receive 10 units of Product F at KSh 400 each
3. Record a sale with:
   - 2 units of Product E at KSh 500 each
   - 3 units of Product F at KSh 600 each
4. Verify:
   - Product E: COGS = 2 × 300 = 600, Revenue = 2 × 500 = 1,000, Profit = 400
   - Product F: COGS = 3 × 400 = 1,200, Revenue = 3 × 600 = 1,800, Profit = 600
   - Total: COGS = 1,800, Revenue = 2,800, Profit = 1,000, Margin ≈ 35.71%

**Expected Result:**
- Receipt shows total COGS: KSh 1,800
- Receipt shows total Profit: KSh 1,000
- Receipt shows Margin: 35.71%
- Each product's batch quantity_remaining updated correctly

---

### Test Case 7: Zero Cost Batch
**Description:** Handle batches with zero cost (free inventory)

**Steps:**
1. Create an inventory batch with unit_cost = 0
2. Record a sale of items from this batch
3. Verify:
   - COGS = 0
   - Profit = Revenue (100% margin)
   - No errors

**Expected Result:**
- Receipt shows COGS: KSh 0
- Receipt shows Profit = Total
- Receipt shows Margin: 100%

---

## 📋 Test Execution Checklist

| Test Case | Description | Status | Notes |
|-----------|-------------|--------|-------|
| TC1 | Basic FIFO Sale | ⬜ | |
| TC2 | Multi-Batch FIFO Sale | ⬜ | |
| TC3 | Partial Batch Consumption | ⬜ | |
| TC4 | Service Product (No FIFO) | ⬜ | |
| TC5 | Insufficient Stock | ⬜ | |
| TC6 | Multiple Products in One Sale | ⬜ | |
| TC7 | Zero Cost Batch | ⬜ | |

---

## 🛠️ Test Setup

### Prerequisites
1. Supabase database with migration 0024 applied
2. Test products created in database
3. Test branches created
4. Test customers created
5. Flutter app connected to test database

### Test Data Setup SQL
```sql
-- Create test branch
INSERT INTO branches (id, name) VALUES ('test-branch-uuid', 'Test Branch')
ON CONFLICT DO NOTHING;

-- Create test products
INSERT INTO products (id, name, product_type, sale_price, cost_price, is_active)
VALUES 
  ('product-a-uuid', 'Product A', 'refill', 800, 500, true),
  ('product-b-uuid', 'Product B', 'refill', 800, 500, true),
  ('product-c-uuid', 'Product C', 'refill', 900, 600, true),
  ('product-d-uuid', 'Product D', 'refill', 500, 400, true),
  ('product-e-uuid', 'Product E', 'refill', 500, 300, true),
  ('product-f-uuid', 'Product F', 'refill', 600, 400, true),
  ('service-uuid', 'Service Product', 'service', 1000, 0, true)
ON CONFLICT DO NOTHING;

-- Create test customer
INSERT INTO customers (id, name, email, credit_limit)
VALUES ('customer-uuid', 'Test Customer', 'test@example.com', 0)
ON CONFLICT DO NOTHING;

-- Initialize stock with batches
SELECT admin_init_stock(
  'test-branch-uuid'::uuid,
  '[{"product_id": "product-a-uuid", "quantity": 10, "cost_price": 500}]'::jsonb
);
```

---

## 📊 Test Results Template

### Test Case: [Name]
**Date:** 
**Tester:** 
**Status:** ✅ Pass / ❌ Fail / ⚠️ Partial

**Actual Results:**

**Expected Results:**

**Discrepancies:**

**Screenshots/Logs:**

---

## 🎯 Acceptance Criteria

For the FIFO implementation to be considered complete:

1. ✅ All test cases pass
2. ✅ No Flutter analyze errors
3. ✅ No Flutter analyze warnings
4. ✅ All edge cases handled (service products, insufficient stock, etc.)
5. ✅ Receipt displays COGS, Profit, and Margin correctly
6. ✅ FIFO data persists and can be queried
7. ✅ Performance is acceptable (no slow queries)

---

**Next Steps:**
1. Execute test cases
2. Fix any failures
3. Document results
4. Commit passing tests to repository

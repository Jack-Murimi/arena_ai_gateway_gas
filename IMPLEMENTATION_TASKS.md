# FIFO Implementation - Actionable Tasks

## 🎯 Current Status
After analyzing the codebase and database migration 0024, I discovered:

**✅ COMPLETE - Database Layer:**
- All tables, views, functions, and RPCs are implemented
- `record_sale` RPC **already handles FIFO allocation** via `consume_inventory_fifo()`
- `admin_receive_order` and `admin_init_stock` RPCs **already create inventory batches**

**⚠️ PARTIAL - Flutter Layer:**
- Models exist ✅
- Repository exists ✅
- Stock page UI shows cost/profit ✅
- BUT: Sale recording doesn't use FIFO data from RPC
- BUT: No way to view FIFO allocations for a sale
- BUT: No batch creation when receiving stock via Flutter (if not using RPCs)

---

## 📋 Task List (Prioritized)

### 🔴 CRITICAL: Verify Database RPC Behavior
**Task:** Test that `record_sale` RPC returns FIFO cost data

```sql
-- Test the RPC directly in Supabase SQL editor
SELECT * FROM record_sale(
  '2026-09-03'::date,
  'branch-uuid',
  'customer-uuid',
  NULL,
  '[{"product_id": "product-uuid", "quantity": 2, "unit_price": 1000}]'::jsonb,
  '[]'::jsonb,
  'cash',
  2000,
  NULL,
  NULL
);
```

**Expected:** Should return `total_cost` and `profit` fields

---

### 🟡 HIGH PRIORITY: Update Sale Model & Repository

#### Task 1: Update Sale Model to include FIFO data
**File:** `lib/features/sales/models/sale.dart`

Add fields:
- `totalCost` (double)
- `totalProfit` (double)
- `profitMarginPercentage` (double)

#### Task 2: Update SaleRepository to expose FIFO data
**File:** `lib/features/sales/data/sale_repository.dart`

The `recordSale()` method already calls the RPC which returns:
```json
{
  "sale_id": "...",
  "invoice_no": "...",
  "total": 1000,
  "amount_paid": 1000,
  "balance_due": 0,
  "payment_status": "paid",
  "total_cost": 700,      // <-- FIFO cost
  "profit": 300          // <-- Profit
}
```

**Action:** Update return type to include these fields

#### Task 3: Add FIFO allocation query methods
**File:** `lib/features/sales/data/sale_repository.dart`

Add methods:
```dart
Future<List<SaleFifoAllocation>> fetchSaleAllocations(String saleId) async {
  // Fetch allocations for a specific sale
}

Future<FifoCostSummary> fetchSaleFifoSummary(String saleId) async {
  // Fetch cost summary for a sale
}
```

---

### 🟡 HIGH PRIORITY: Update Sale Recording to Use RPC FIFO Data

**File:** `lib/features/sales/widgets/sale_form.dart`

When a sale is recorded, the RPC returns `total_cost` and `profit`. 
**Action:** Capture and display this data in the result dialog

Current code:
```dart
final result = await _repo.recordSale(...);
_showResult(result);
```

Should capture:
```dart
final result = await _repo.recordSale(...);
final totalCost = result['total_cost'] as double? ?? 0;
final profit = result['profit'] as double? ?? 0;
// Pass these to _showResult or display separately
```

---

### 🟡 MEDIUM PRIORITY: Update Receipt Page to Show FIFO Data

**File:** `lib/features/sales/receipt_page.dart`

Add to receipt display:
- Cost of Goods Sold (COGS)
- Profit
- Profit Margin %
- Batch allocations (which batches were consumed)

---

### 🟡 MEDIUM PRIORITY: Add FIFO View to Sale Details

**File:** New or existing sale detail page

Create a view that shows:
- For each sale item: which batches were consumed, at what cost
- Total COGS for the sale
- Total profit for the sale
- Profit margin %

---

### ⚪ MEDIUM PRIORITY: Verify Stock Receipt Creates Batches

**Check:** Does the Flutter app use `admin_receive_order` RPC or does it directly update stock?

If it uses the RPC:
- ✅ Batches are already created automatically

If it doesn't use the RPC:
- ❌ Need to add batch creation logic

**File to check:** `lib/features/inventory/order_form_page.dart`

---

### ⚪ LOW PRIORITY: Add FIFO Reports

1. **FIFO Cost Report** - Show COGS vs Revenue by date range
2. **Inventory Aging Report** - Show old batches that need to be sold
3. **Profit Margin Report** - Show margins by product/branch

---

## 🎯 Implementation Strategy

### Step 1: Verify Current State (30 min)
- [ ] Test `record_sale` RPC returns FIFO data
- [ ] Check if Flutter uses RPC for stock receipt
- [ ] Verify FIFO tables exist in Supabase

### Step 2: Update Sale Model & Repository (1 hour)
- [ ] Add FIFO fields to Sale model
- [ ] Update `recordSale()` to expose FIFO data
- [ ] Add `fetchSaleAllocations()` method
- [ ] Add `fetchSaleFifoSummary()` method

### Step 3: Update Sale Form (30 min)
- [ ] Display FIFO cost/profit in result dialog
- [ ] Ensure data flows correctly

### Step 4: Update Receipt Page (1 hour)
- [ ] Add COGS display
- [ ] Add profit display
- [ ] Add profit margin display

### Step 5: Add FIFO Detail View (2 hours)
- [ ] Create FIFO allocation detail page
- [ ] Show batch breakdown for each sale

### Step 6: Test Everything (2 hours)
- [ ] Test sale recording with FIFO
- [ ] Test FIFO data display
- [ ] Test edge cases

---

## 📊 Estimated Timeline

| Step | Task | Time Estimate | Priority |
|------|------|---------------|----------|
| 1 | Verify current state | 30 min | 🔴 Critical |
| 2 | Update models & repository | 1 hour | 🟡 High |
| 3 | Update sale form | 30 min | 🟡 High |
| 4 | Update receipt page | 1 hour | 🟡 High |
| 5 | Add FIFO detail view | 2 hours | 🟡 Medium |
| 6 | Testing | 2 hours | 🟡 High |
| **Total** | | **7 hours** | |

---

## 🎯 Quick Wins (Can Do Now)

1. **Test the RPC** - 5 minutes
   ```bash
   # In Supabase SQL editor
   SELECT * FROM record_sale(...);
   ```

2. **Check Order Form** - 5 minutes
   ```bash
   grep -n "admin_receive_order\|record_sale" lib/features/inventory/order_form_page.dart
   ```

3. **Update Sale Model** - 15 minutes
   Add 3 fields to capture FIFO data

---

## 📝 Implementation Notes

### Key Insight
The **database layer is complete**. The `record_sale` RPC already:
- Calls `consume_inventory_fifo()` to allocate inventory
- Creates `sale_fifo_allocations` records
- Updates `quantity_remaining` in batches
- Returns `total_cost` and `profit`

**We just need to use this data in Flutter!**

### Files to Modify
1. `lib/features/sales/models/sale.dart` - Add FIFO fields
2. `lib/features/sales/data/sale_repository.dart` - Expose FIFO data
3. `lib/features/sales/widgets/sale_form.dart` - Display FIFO data
4. `lib/features/sales/receipt_page.dart` - Show COGS/profit
5. New: FIFO detail page

### Edge Cases to Handle
1. **Service products** - No FIFO allocation (RPC should handle this)
2. **Insufficient stock** - RPC throws exception, Flutter should catch
3. **Multiple batches** - RPC handles allocation across batches
4. **Zero cost** - Handle batches with unit_cost = 0
5. **Null values** - Ensure all fields have fallbacks

---

**Next Action:** Start with Step 1 - Verify the RPC returns FIFO data, then proceed to Step 2.

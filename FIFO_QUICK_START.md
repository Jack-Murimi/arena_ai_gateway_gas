# FIFO Inventory Costing - Quick Start Guide

## What's New?

The Stock page now shows **Cost Price, Selling Price, and Expected Profit** for all inventory items!

### New Metrics at the Top
- **Inventory Value**: Total cost value of all stock
- **Expected Profit**: Total potential profit at current prices
- **Profit Margin**: Average profit margin percentage

### New Columns in Tables
- **Cost Price**: The average FIFO cost per unit
- **Selling Price**: The current selling price per unit
- **Profit/Unit**: Expected profit per unit (Selling - Cost)

### Mobile Cards
Each product card now shows:
- Stock quantity and status
- Cost Price
- Selling Price
- Profit per unit (green = profitable, red = loss)

## How FIFO Works

### Behind the Scenes
1. **Batches**: Each purchase creates a batch with its own cost price
2. **FIFO**: Sales consume from the oldest batch first (First-In, First-Out)
3. **Tracking**: System records which batches were used for each sale
4. **Accuracy**: Historical sales don't change when new purchases arrive

### Example
```
Batch 1: 10 cylinders @ KSh 2,200 (Jan 1)
Batch 2: 10 cylinders @ KSh 2,300 (Jan 15)

Sell 6 cylinders:
- Uses 6 from Batch 1 (oldest first)
- Cost: 6 × 2,200 = KSh 13,200
- Revenue: 6 × 2,500 = KSh 15,000
- Profit: KSh 1,800
```

## What You Need to Do

### 1. Apply the Database Migration

The FIFO system needs the database tables to work properly.

```bash
# Navigate to your project
cd arena_ai_gateway_gas

# Apply the migration
supabase db push
```

**OR** apply manually via Supabase Dashboard:
- Run the SQL in `supabase/migrations/0024_fifo_inventory_batches.sql`

### 2. Test It Out

After applying the migration:
1. Open the Stock page
2. You should see the new metrics at the top
3. All products should show cost price, selling price, and profit
4. Service products will show "—" (not applicable)

### 3. Verify Data

- Check that cost prices match your purchase orders
- Verify selling prices match your product catalogue
- Confirm profit calculations are correct

## Troubleshooting

### If you see zeros or missing data:
1. **Migration not applied**: Make sure migration 0024 is applied to your database
2. **No batch data**: New purchases will create batches. Existing stock needs to be initialized
3. **Cache issue**: Try refreshing the page or clearing app cache

### To initialize existing stock with costs:
Use the stock initialization feature to set opening stock with costs.

## Key Benefits

✅ **Accurate Cost Tracking**: Know exactly what you paid for each item
✅ **Historical Accuracy**: Past sales don't change when new purchases arrive
✅ **Profit Visibility**: See expected profit for every product
✅ **Better Decisions**: Identify low-margin products quickly
✅ **FIFO Compliance**: Follows accounting best practices

## Need Help?

Check these files for implementation details:
- `FIFO_IMPLEMENTATION_SUMMARY.md` - Full implementation details
- `supabase/migrations/0024_fifo_inventory_batches.sql` - Database schema
- `lib/features/inventory/models/inventory_batch.dart` - Data models
- `lib/features/inventory/stock_page.dart` - UI implementation

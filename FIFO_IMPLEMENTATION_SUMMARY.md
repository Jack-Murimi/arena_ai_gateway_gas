# FIFO Inventory Costing System - Implementation Summary

## Overview
This document summarizes the implementation of the FIFO (First-In-First-Out) inventory costing system for Gateway Gas Enterprises, which tracks cost prices, selling prices, and calculates expected profits for stock items.

## Changes Made

### 1. Database Migration (Already Created)
- **File**: `supabase/migrations/0024_fifo_inventory_batches.sql`
- **Status**: ✅ Created (needs to be applied to Supabase)
- **Contents**:
  - `inventory_batches` table - Tracks each purchase batch with specific costs
  - `sale_fifo_allocations` table - Tracks which batches were consumed by each sale
  - Views: `current_inventory_batches`, `sales_fifo_view`
  - Modified RPCs: `admin_receive_order`, `record_sale`, `admin_init_stock`
  - Helper functions: `get_oldest_inventory_batch`, `consume_inventory_fifo`, `get_product_selling_price`
  - RLS policies for security

### 2. Models (Already Created)
- **File**: `lib/features/inventory/models/inventory_batch.dart`
- **Status**: ✅ Created
- **Classes**:
  - `InventoryBatch` - Represents a batch of inventory with cost tracking
  - `SaleFifoAllocation` - Represents FIFO allocations for sale items
  - `FifoCostSummary` - Summary of FIFO cost information

### 3. Repository (Already Created & Enhanced)
- **File**: `lib/features/inventory/data/inventory_batch_repository.dart`
- **Status**: ✅ Created & Enhanced
- **New Method**: `fetchProductSellingPricesBatch()` - Batch fetch selling prices for multiple products

### 4. Stock Item Model (Enhanced)
- **File**: `lib/features/inventory/models/stock_item.dart`
- **Status**: ✅ Enhanced
- **Changes to `ProductStockRow`**:
  - Added `sellingPrice` and `costPrice` fields
  - Added `branchCosts` map (branchId -> average cost)
  - Added `branchSellingPrices` map (branchId -> selling price)
  - Added helper methods:
    - `costPriceFor(branchId)` - Get cost price for a branch
    - `sellingPriceFor(branchId)` - Get selling price for a branch
    - `expectedProfitPerUnitFor(branchId)` - Calculate profit per unit
    - `totalExpectedProfitFor(branchId)` - Calculate total expected profit
    - `totalInventoryValueFor(branchId)` - Calculate total inventory value at cost

### 5. Stock Page UI (Enhanced)
- **File**: `lib/features/inventory/stock_page.dart`
- **Status**: ✅ Enhanced
- **Changes**:
  
  #### Imports Added
  ```dart
  import '../../core/utils/num_parse.dart';
  import 'data/inventory_batch_repository.dart';
  import 'models/inventory_batch.dart';
  ```
  
  #### State Variables Added
  ```dart
  final _batchRepo = InventoryBatchRepository();
  final Map<String, double> _productSellingPrices = {};
  final Map<String, double> _productAverageCosts = {};
  ```
  
  #### Data Loading Enhanced
  - Modified `_loadData()` to call `_loadProductPricesAndCosts()`
  - Added `_loadProductPricesAndCosts()` method to fetch:
    - Selling prices for all products in stock (batch fetch)
    - Average FIFO costs for each product at each branch
  
  #### Metrics Added
  - `_metricTotalInventoryValue` - Total inventory value at cost
  - `_metricTotalExpectedProfit` - Total expected profit for all stock
  - `_metricAverageProfitMargin` - Average profit margin percentage
  
  #### UI Views Updated
  
  **Summary Metrics Row**:
  - Added 3 new metric cards:
    - Inventory Value (KSh amount)
    - Expected Profit (KSh amount)
    - Profit Margin (percentage)
  
  **Multi-Branch Matrix Table**:
  - Added 3 new columns:
    - Cost Price (per unit)
    - Selling Price (per unit)
    - Profit/Unit (calculated as Selling - Cost)
  
  **Single-Branch Table**:
  - Added 3 new columns:
    - Cost Price (per unit)
    - Selling Price (per unit)
    - Profit/Unit (calculated as Selling - Cost)
  
  **Mobile Compact Cards**:
  - Enhanced right-side column to show:
    - Stock quantity badge
    - Cost Price
    - Selling Price
    - Profit per unit (color-coded: green for positive, red for negative)
  
  #### Helper Widgets Added
  - `_profitCell(double profit)` - Displays profit with appropriate color coding

## FIFO Costing Logic

### How It Works
1. **Batch Tracking**: Each purchase creates an inventory batch with:
   - Product ID
   - Branch ID
   - Quantity received
   - Quantity remaining
   - Unit cost at time of purchase
   - Purchase date

2. **FIFO Consumption**: When a sale occurs:
   - The system consumes from the oldest batch first
   - Records allocations in `sale_fifo_allocations` table
   - Updates remaining quantities in batches
   - Calculates actual cost of goods sold (COGS)

3. **Average Cost Calculation**:
   - For display purposes, shows weighted average cost based on remaining quantities
   - Formula: `SUM(quantity_remaining * unit_cost) / SUM(quantity_remaining)`

4. **Profit Calculation**:
   - Per Unit: `Selling Price - Average Cost`
   - Total: `(Selling Price - Average Cost) * Quantity`

## UI Display

### Desktop/Tablet Views
- **Multi-Branch Matrix**: Shows cost, selling price, and profit columns for each product
- **Single-Branch Table**: Shows the same cost information in a focused view
- **Summary Cards**: Shows total inventory value, expected profit, and profit margin

### Mobile View
- **Compact Cards**: Each product card shows:
  - Product name, type, brand, size
  - Stock quantity with status indicator
  - Cost Price
  - Selling Price
  - Profit per unit (color-coded)

### Color Coding
- **Profit (Positive)**: Green (AppColors.success)
- **Profit (Negative)**: Red (AppColors.danger)
- **Cost Price**: Default text color
- **Selling Price**: Primary color (AppColors.primary)

## Next Steps (To Be Completed)

1. **Apply Migration 0024 to Supabase**
   ```bash
   supabase db push
   # Or apply manually via Supabase dashboard
   ```

2. **Test FIFO Scenarios**
   - Create test products with different cost prices
   - Receive inventory at different costs
   - Make sales and verify FIFO consumption
   - Verify profit calculations

3. **Performance Optimization** (Optional)
   - Consider caching product prices
   - Consider batch fetching all data in a single RPC
   - Consider adding indexes for better query performance

## Example Scenario

```
Product: Afrigas 13kg

Batch 1: 10 cylinders @ KSh 2,200 (received Jan 1)
Batch 2: 10 cylinders @ KSh 2,300 (received Jan 15)

Current Stock: 20 cylinders
Average Cost: KSh 2,250
Selling Price: KSh 2,500

Sell 6 cylinders:
- Consumes 6 from Batch 1 (oldest first)
- Cost: 6 × 2,200 = KSh 13,200
- Revenue: 6 × 2,500 = KSh 15,000
- Profit: KSh 1,800
- Profit/Unit: KSh 300

Remaining:
- Batch 1: 4 cylinders @ KSh 2,200
- Batch 2: 10 cylinders @ KSh 2,300
- New Average Cost: (4×2200 + 10×2300) / 14 = KSh 2,271
```

## Backward Compatibility

- All existing functionality preserved
- Service products show "—" for cost/selling price (not applicable)
- If no cost data exists, defaults to 0
- Existing stock quantities and movements unchanged

## Files Modified

1. `lib/features/inventory/stock_page.dart` - Main UI integration
2. `lib/features/inventory/models/stock_item.dart` - Enhanced ProductStockRow
3. `lib/features/inventory/data/inventory_batch_repository.dart` - Added batch fetch method

## Files Created (Previously)

1. `supabase/migrations/0024_fifo_inventory_batches.sql` - Database migration
2. `lib/features/inventory/models/inventory_batch.dart` - FIFO models
3. `lib/features/inventory/data/inventory_batch_repository.dart` - Repository

## Testing Checklist

- [ ] Apply migration 0024 to Supabase
- [ ] Verify stock page loads without errors
- [ ] Verify cost prices display correctly
- [ ] Verify selling prices display correctly
- [ ] Verify profit calculations are correct
- [ ] Verify summary metrics update correctly
- [ ] Test with service products (should show "—")
- [ ] Test with multiple branches
- [ ] Test with low/out of stock items
- [ ] Test mobile view layout
- [ ] Test desktop/tablet view layout

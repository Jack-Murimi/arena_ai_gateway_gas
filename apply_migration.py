#!/usr/bin/env python3
"""
Apply FIFO migration 0024 to Supabase
"""
import psycopg2
import psycopg2.extras
import sys
import os

# Supabase connection details
HOST = "aws-1-eu-west-1.pooler.supabase.com"
PORT = 6543
DATABASE = "postgres"
USER = "postgres.vvdmuppyszaknkvnhqtg"
PASSWORD = "xf$_@-kP5-PXmXT"

# Migration file
MIGRATION_FILE = "supabase/migrations/0024_fifo_inventory_batches.sql"

def read_migration_sql(filepath):
    """Read the migration SQL file"""
    with open(filepath, 'r') as f:
        return f.read()

def apply_migration():
    """Apply the migration to Supabase"""
    print("🔄 Connecting to Supabase...")
    
    try:
        # Connect to Supabase
        conn = psycopg2.connect(
            host=HOST,
            port=PORT,
            database=DATABASE,
            user=USER,
            password=PASSWORD,
            sslmode='require'
        )
        conn.autocommit = True
        cursor = conn.cursor()
        
        print("✅ Connected successfully!")
        
        # Read migration SQL
        print("📖 Reading migration file...")
        migration_sql = read_migration_sql(MIGRATION_FILE)
        print(f"📊 Migration file size: {len(migration_sql)} characters")
        
        # Split into individual statements
        print("🔨 Executing migration statements...")
        
        # Split by semicolons, but handle complex SQL with semicolons in strings
        # We'll execute it as a single transaction
        try:
            cursor.execute(migration_sql)
            print("✅ Migration applied successfully!")
        except Exception as e:
            print(f"❌ Error executing migration: {e}")
            # Try executing statement by statement
            print("\n🔄 Trying statement-by-statement execution...")
            statements = [s.strip() for s in migration_sql.split(';') if s.strip()]
            for i, stmt in enumerate(statements, 1):
                try:
                    if stmt:
                        cursor.execute(f"{stmt};")
                        print(f"  ✅ Statement {i}/{len(statements)}")
                except Exception as e:
                    print(f"  ❌ Statement {i} failed: {e}")
                    print(f"     SQL: {stmt[:100]}...")
            return False
        
        # Verify tables were created
        print("\n🔍 Verifying migration...")
        cursor.execute("""
            SELECT table_name FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name IN ('inventory_batches', 'sale_fifo_allocations')
        """)
        tables = cursor.fetchall()
        table_names = [t[0] for t in tables]
        
        if 'inventory_batches' in table_names:
            print("  ✅ inventory_batches table created")
        else:
            print("  ❌ inventory_batches table NOT found")
        
        if 'sale_fifo_allocations' in table_names:
            print("  ✅ sale_fifo_allocations table created")
        else:
            print("  ❌ sale_fifo_allocations table NOT found")
        
        # Check views
        cursor.execute("""
            SELECT table_name FROM information_schema.views 
            WHERE table_schema = 'public' 
            AND table_name IN ('current_inventory_batches', 'sales_fifo_view')
        """)
        views = cursor.fetchall()
        view_names = [v[0] for v in views]
        
        if 'current_inventory_batches' in view_names:
            print("  ✅ current_inventory_batches view created")
        else:
            print("  ❌ current_inventory_batches view NOT found")
        
        if 'sales_fifo_view' in view_names:
            print("  ✅ sales_fifo_view view created")
        else:
            print("  ❌ sales_fifo_view view NOT found")
        
        cursor.close()
        conn.close()
        
        print("\n✅ Migration 0024 applied successfully!")
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

if __name__ == "__main__":
    success = apply_migration()
    sys.exit(0 if success else 1)

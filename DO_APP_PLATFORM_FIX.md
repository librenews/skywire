# DigitalOcean App Platform - Quick Fix

## The Problem

You're seeing this error:
```
invalid URL ${db.DATABASE_URL}, host is not present
```

This means the environment variable `${db.DATABASE_URL}` is **not being expanded** - it's being passed literally as a string.

---

## Solution: Set DATABASE_URL Directly

In **DigitalOcean App Platform**:

### Step 1: Get Your Database Connection String

1. Go to your **Managed Database**
2. Click **Connection Details** 
3. Select **Connection String**
4. Copy the full string (should look like):
   ```
   postgresql://doadmin:SOME_PASSWORD@db-postgresql-nyc3-12345-do-user-123456-0.b.db.ondigitalocean.com:25060/defaultdb?sslmode=require
   ```

### Step 2: Set Environment Variable in App Platform

1. Go to your **App** → **Settings** → **App-Level Environment Variables**
2. **Edit** or **Add** the `DATABASE_URL` variable
3. **Instead of** `${db.DATABASE_URL}`, paste the **actual connection string**:
   ```
   DATABASE_URL=postgresql://doadmin:YOUR_PASSWORD@db-postgresql-nyc3-12345-do-user-123456-0.b.db.ondigitalocean.com:25060/defaultdb?sslmode=require
   ```

### Step 3: Verify Other Variables

Make sure you also have:
```
SECRET_KEY_BASE=<your generated secret>
PHX_SERVER=true
EVENT_RETENTION_DAYS=7
```

### Step 4: Redeploy

Click **Actions** → **Force Rebuild and Deploy**

---

## Why This Happened

DigitalOcean's `${db.DATABASE_URL}` syntax works for **some** buildpacks, but not for custom Dockerfiles. When using a Dockerfile, you need to provide the actual connection string.

---

## Alternative: Use Component-Level Variables

If you want to use the `${db.DATABASE_URL}` syntax:

1. Go to your database component
2. Note the connection string
3. In your app component settings, use the **actual value** instead of the variable reference

The `${db.VAR}` syntax is meant for DigitalOcean's managed buildpacks, not Docker builds.

---

## Quick Checklist

- [ ] Copy database connection string from Database → Connection Details
- [ ] Go to App Platform → Your App → Settings → Environment Variables
- [ ] Set `DATABASE_URL` to the **full connection string** (not `${db.DATABASE_URL}`)
- [ ] Verify `SECRET_KEY_BASE` is set
- [ ] Verify `PHX_SERVER=true` is set
- [ ] Click "Save" and redeploy

After redeployment, check the logs - you should see the app start successfully!

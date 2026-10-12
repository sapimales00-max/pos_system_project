# PIN authentication

All application users sign in with a six-digit PIN. PINs are stored as
`scrypt` hashes; never store or distribute a PIN as plain text.

## First admin setup

1. Back up the database before deploying the authentication migration. The
   migration removes the legacy `users.email` and `users.password_hash` columns.
2. Set `ADMIN_BOOTSTRAP_TOKEN` in the backend environment to a unique,
   randomly generated secret of at least 32 characters. Do not commit or share
   this value.
3. Start the backend, open the application, and use the admin PIN setup form.
   Enter the bootstrap token and choose a six-digit admin PIN.
4. Keep the bootstrap token private. The endpoint refuses bootstrap once any
   admin has a PIN.

## Recovering locked-out admin accounts

Recovery requires direct database access and a maintenance window:

1. Stop the backend and back up the database.
2. Clear PIN hashes for admin accounts:

   ```sql
   UPDATE users
   SET pin_hash = NULL
   WHERE role IN ('ADMIN', 'OWNER');
   ```

3. Ensure the backend has a private `ADMIN_BOOTSTRAP_TOKEN` of at least 32
   characters, then restart it.
4. Use the application admin PIN setup form with that token. Bootstrap sets a
   PIN on the oldest existing admin account. Other admin PINs can then be reset
   from account management.

Do not run the recovery SQL while the backend is running: existing in-memory
sessions may remain active until the process is restarted.

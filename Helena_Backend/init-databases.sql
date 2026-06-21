-- Dijalankan otomatis oleh container MySQL saat pertama kali start
-- (lihat docker-compose.yml: /docker-entrypoint-initdb.d/)
-- Setiap service punya database sendiri -- bukan digabung jadi satu seperti sebelumnya.

CREATE DATABASE IF NOT EXISTS db_auth;
CREATE DATABASE IF NOT EXISTS db_billing;
CREATE DATABASE IF NOT EXISTS db_pocket_money;

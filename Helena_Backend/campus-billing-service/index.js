const express = require('express');
const mysql = require('mysql2');

const app = express();
const PORT = 4002;

app.use(express.json());

// Koneksi ke Database Utama
const db = mysql.createConnection({
    host: 'kampus-db', 
    user: 'root',
    password: 'rahasia_db_password',
    database: 'db_pocket_money' // Kita gabungkan di database yang sama untuk efisiensi
});

db.connect(err => {
    if (err) {
        console.error('❌ Gagal koneksi ke MySQL:', err.message);
        return;
    }
    console.log('🚀 Terhubung ke MySQL Kampus DB!');
    
    // 1. Buat Tabel Tagihan
    const createTable = `
        CREATE TABLE IF NOT EXISTS tagihan (
            nim VARCHAR(20) PRIMARY KEY,
            ukt_total INT NOT NULL,
            ukt_dibayar INT NOT NULL,
            status VARCHAR(20) NOT NULL
        )
    `;
    db.query(createTable, (err) => {
        if (err) console.error('Gagal membuat tabel tagihan:', err.message);
        
        // 2. Database Seeding (Suntik data awal jika tabel kosong)
        db.query("SELECT COUNT(*) AS count FROM tagihan", (err, results) => {
            if (err) return console.error(err.message);

            if (results[0].count === 0) {
                const insertData = `
                    INSERT INTO tagihan (nim, ukt_total, ukt_dibayar, status) 
                    VALUES 
                    ('123456', 5000000, 5000000, 'Lunas'),
                    ('654321', 7500000, 2500000, 'Belum Lunas')
                `;
                db.query(insertData, (err) => {
                    if (err) console.error(err.message);
                    else console.log('✅ Data Tagihan awal berhasil disuntikkan!');
                });
            }
        });
    });
});

// Endpoint GET Data Tagihan dari MySQL
app.get('/tagihan/:nim', (req, res) => {
    const studentNim = req.params.nim;
    
    db.query('SELECT * FROM tagihan WHERE nim = ?', [studentNim], (err, results) => {
        // STANDAR JSON: Gagal (Error Sistem)
        if (err) {
            return res.status(500).json({ 
                status: 'error', 
                message: 'Gagal mengambil data tagihan.',
                data: null
            });
        }
        
        if (results.length > 0) {
            // STANDAR JSON: Sukses
            res.status(200).json({ 
                status: 'success', 
                message: 'Data tagihan berhasil diambil.',
                data: results[0] 
            });
        } else {
            // STANDAR JSON: Gagal (Data tidak ditemukan)
            res.status(404).json({ 
                status: 'error', 
                message: 'Data tagihan tidak ditemukan.',
                data: null 
            });
        }
    });
});

// --- ENDPOINT BARU KHUSUS ADMIN: MENERBITKAN TAGIHAN UKT ---
app.post('/tagihan', (req, res) => {
    const { nim, ukt_total } = req.body;

    if (!nim || !ukt_total) {
        return res.status(400).json({ status: 'error', message: 'NIM dan Total UKT wajib diisi!', data: null });
    }

    // Menggunakan INSERT ... ON DUPLICATE KEY UPDATE 
    // Artinya: Jika belum ada, buatkan baru. Jika sudah ada, perbarui nominalnya.
    const insertQuery = `
        INSERT INTO tagihan (nim, ukt_total, ukt_dibayar, status) 
        VALUES (?, ?, 0, 'Belum Lunas') 
        ON DUPLICATE KEY UPDATE ukt_total = ?, status = 'Belum Lunas'
    `;

    db.query(insertQuery, [nim, ukt_total, ukt_total], (err, result) => {
        if (err) {
            console.error(err);
            return res.status(500).json({ status: 'error', message: 'Gagal menerbitkan tagihan.', data: null });
        }
        res.status(201).json({ 
            status: 'success', 
            message: `Tagihan UKT sebesar Rp ${ukt_total} untuk NIM ${nim} berhasil diterbitkan!`, 
            data: null 
        });
    });
});

// --- ENDPOINT PEMBAYARAN UKT (MAHASISWA) ---
app.put('/tagihan/:nim/bayar', (req, res) => {
    const nim = req.params.nim;
    
    // Query ini akan mengubah ukt_dibayar menjadi sama dengan ukt_total, dan status jadi Lunas
    const updateQuery = `
        UPDATE tagihan 
        SET ukt_dibayar = ukt_total, status = 'Lunas' 
        WHERE nim = ? AND status != 'Lunas'
    `;
    
    db.query(updateQuery, [nim], (err, result) => {
        if (err) {
            console.error(err);
            return res.status(500).json({ status: 'error', message: 'Gagal memproses pembayaran.', data: null });
        }
        
        // Jika tidak ada baris yang berubah, berarti tagihan sudah lunas atau NIM tidak ada
        if (result.affectedRows === 0) {
            return res.status(400).json({ status: 'error', message: 'Tagihan sudah lunas atau tidak ditemukan.', data: null });
        }

        res.status(200).json({ status: 'success', message: 'Pembayaran UKT berhasil diproses!', data: null });
    });
});

// Ditambahkan '0.0.0.0' agar aman untuk jaringan Docker
app.listen(PORT, '0.0.0.0', () => {
    console.log(`💰 Campus Billing Service aktif di port ${PORT}`);
});
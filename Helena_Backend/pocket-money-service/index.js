const express = require('express');
const mysql = require('mysql2');

const app = express();
const PORT = 4003;

app.use(express.json());

// 1. Konfigurasi Koneksi ke Kontainer MySQL Docker
const db = mysql.createConnection({
    host: 'kampus-db', // Memanggil nama service di docker-compose
    user: 'root',
    password: 'rahasia_db_password',
    database: 'db_pocket_money'
});

// Hubungkan ke MySQL dan buat tabel transaksi otomatis jika belum ada
db.connect(err => {
    if (err) {
        console.error('❌ Gagal koneksi ke MySQL:', err.message);
        return;
    }
    console.log('🚀 Terhubung ke Database MySQL Kampus!');

    const createTableQuery = `
        CREATE TABLE IF NOT EXISTS transaksi (
            id INT AUTO_INCREMENT PRIMARY KEY,
            nim VARCHAR(20) NOT NULL,
            nominal INT NOT NULL,
            jenis_transaksi ENUM('pemasukan', 'pengeluaran') NOT NULL,
            keterangan TEXT,
            tanggal DATE NOT NULL
        )
    `;
    db.query(createTableQuery, (err) => {
        if (err) console.error('Gagal membuat tabel:', err.message);
    });
});

// 2. Endpoint GET: Mengambil riwayat dengan Paginasi
app.get('/riwayat/:nim', (req, res) => {
    const nim = req.params.nim;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 5; 
    const offset = (page - 1) * limit;

    const sql = 'SELECT * FROM transaksi WHERE nim = ? ORDER BY tanggal DESC, id DESC LIMIT ? OFFSET ?';
    
    db.query(sql, [nim, limit, offset], (err, results) => {
        // STANDAR JSON: Gagal
        if (err) {
            return res.status(500).json({ 
                status: 'error', 
                message: 'Gagal mengambil riwayat transaksi.',
                data: null 
            });
        }
        
        // STANDAR JSON: Sukses
        res.status(200).json({ 
            status: 'success', 
            message: 'Riwayat transaksi berhasil diambil.',
            data: results 
        });
    });
});

// 3. Endpoint POST: Menyimpan transaksi ke Database
app.post('/transaksi', (req, res) => {
    const { nim, nominal, jenis_transaksi, keterangan, tanggal } = req.body;

    // Pengamanan Input (Validasi Basic)
    if (!nim || !nominal || !jenis_transaksi || !tanggal) {
         return res.status(400).json({ 
             status: 'error', 
             message: 'Data transaksi tidak lengkap!',
             data: null 
         });
    }

    const queryInsert = 'INSERT INTO transaksi (nim, nominal, jenis_transaksi, keterangan, tanggal) VALUES (?, ?, ?, ?, ?)';

    db.query(queryInsert, [nim, nominal, jenis_transaksi, keterangan, tanggal], (err, result) => {
        if (err) {
            return res.status(500).json({ 
                status: 'error', 
                message: 'Gagal mencatat transaksi ke database.',
                data: null 
            });
        }
        
        res.status(201).json({
            status: 'success',
            message: 'Transaksi berhasil dicatat ke MySQL permanen!',
            data: { id: result.insertId, nim, nominal, jenis_transaksi, keterangan, tanggal }
        });
    });
});

// 4. Endpoint DELETE: Menghapus transaksi berdasarkan ID
app.delete('/transaksi/:id', (req, res) => {
    const transaksiId = req.params.id;

    const sql = `DELETE FROM transaksi WHERE id = ?`;
    db.query(sql, [transaksiId], (err, result) => {
        if (err) {
            console.error('Gagal menghapus transaksi:', err);
            return res.status(500).json({ 
                status: 'error', 
                message: 'Terjadi kesalahan sistem saat menghapus transaksi.',
                data: null 
            });
        }

        if (result.affectedRows === 0) {
            return res.status(404).json({ 
                status: 'error', 
                message: 'Transaksi tidak ditemukan atau sudah dihapus!',
                data: null 
            });
        }

        res.status(200).json({ 
            status: 'success', 
            message: 'Transaksi berhasil dihapus!',
            data: null
        });
    });
});

// 5. Endpoint GET: Ringkasan Saldo (Untuk Pie Chart & Kartu Saldo)
app.get('/ringkasan/:nim', (req, res) => {
    const nim = req.params.nim;
    const sql = `
        SELECT 
            SUM(CASE WHEN jenis_transaksi = 'pemasukan' THEN nominal ELSE 0 END) as total_pemasukan,
            SUM(CASE WHEN jenis_transaksi = 'pengeluaran' THEN nominal ELSE 0 END) as total_pengeluaran
        FROM transaksi 
        WHERE nim = ?
    `;
    
    db.query(sql, [nim], (err, results) => {
        if (err) {
            return res.status(500).json({ 
                status: 'error', 
                message: 'Gagal menghitung ringkasan saldo.',
                data: null 
            });
        }
        
        const pemasukan = Number(results[0].total_pemasukan) || 0;
        const pengeluaran = Number(results[0].total_pengeluaran) || 0;
        const saldo = pemasukan - pengeluaran;

        res.status(200).json({ 
            status: 'success', 
            message: 'Ringkasan saldo berhasil dihitung.',
            data: { pemasukan, pengeluaran, saldo } 
        });
    });
});

app.listen(PORT, '0.0.0.0', () => { // Ditambahkan '0.0.0.0' agar aman untuk Docker
    console.log(`[Pocket Money Service] Siap dengan database di port ${PORT}`);
});
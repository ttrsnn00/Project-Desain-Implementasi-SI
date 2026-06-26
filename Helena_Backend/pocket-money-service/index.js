require('dotenv').config();
const express = require('express');
const mysql = require('mysql2');

const app = express();
const PORT = process.env.PORT || 4003;

app.use(express.json());

// 1. Konfigurasi Koneksi ke database khusus Pocket Money (terpisah dari service lain)
// Pakai connection POOL (bukan createConnection tunggal) supaya otomatis
// reconnect kalau koneksi pertama gagal/putus -- mencegah service "mati permanen"
// kalau MySQL belum benar-benar siap saat service ini pertama kali start.
const db = mysql.createPool({
    host: process.env.DB_HOST || 'kampus-db',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || 'db_pocket_money',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

// Coba koneksi dengan retry, supaya error di log jelas dan tabel
// langsung dibuat begitu MySQL benar-benar siap (bukan baru saat query pertama masuk).
function connectWithRetry(retriesLeft = 10) {
    db.getConnection((err, connection) => {
        if (err) {
            console.error(`❌ Gagal koneksi ke MySQL (sisa percobaan: ${retriesLeft}):`, err.message);
            if (retriesLeft > 0) {
                setTimeout(() => connectWithRetry(retriesLeft - 1), 3000);
            } else {
                console.error('❌ Menyerah mencoba konek ke MySQL setelah beberapa kali percobaan.');
            }
            return;
        }
        connection.release();
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
}

connectWithRetry();

// --- MIDDLEWARE OTORISASI ---
// Identitas user diteruskan oleh API Gateway via header (sudah diverifikasi JWT di sana).
// Mahasiswa hanya boleh akses/ubah data miliknya sendiri; admin boleh akses semua.
const authorizeOwnerOrAdmin = (req, res, next) => {
    const requesterNim = req.headers['x-user-nim'];
    const requesterRole = req.headers['x-user-role'];
    const targetNim = req.params.nim;

    if (requesterRole === 'admin' || requesterNim === targetNim) {
        return next();
    }
    return res.status(403).json({
        status: 'error',
        message: 'Anda tidak memiliki akses ke data mahasiswa lain.',
        data: null
    });
};

// 2. Endpoint GET: Mengambil riwayat dengan Paginasi
app.get('/riwayat/:nim', authorizeOwnerOrAdmin, (req, res) => {
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
    const { nominal, jenis_transaksi, keterangan, tanggal } = req.body;
    const requesterRole = req.headers['x-user-role'];
    // NIM diambil dari identitas terverifikasi gateway, BUKAN dari body request,
    // supaya mahasiswa tidak bisa mencatat transaksi atas nama orang lain.
    // Admin boleh menulis atas nama NIM tertentu lewat body (mis. untuk koreksi data).
    const nim = (requesterRole === 'admin' && req.body.nim) ? req.body.nim : req.headers['x-user-nim'];

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
    const requesterNim = req.headers['x-user-nim'];
    const requesterRole = req.headers['x-user-role'];

    // Cek dulu siapa pemilik transaksi ini sebelum menghapus (mencegah IDOR),
    // karena endpoint ini tidak punya :nim di path untuk dicocokkan langsung.
    db.query('SELECT nim FROM transaksi WHERE id = ?', [transaksiId], (err, rows) => {
        if (err) {
            console.error('Gagal mengecek kepemilikan transaksi:', err);
            return res.status(500).json({
                status: 'error',
                message: 'Terjadi kesalahan sistem saat memvalidasi transaksi.',
                data: null
            });
        }

        if (rows.length === 0) {
            return res.status(404).json({
                status: 'error',
                message: 'Transaksi tidak ditemukan atau sudah dihapus!',
                data: null
            });
        }

        if (requesterRole !== 'admin' && rows[0].nim !== requesterNim) {
            return res.status(403).json({
                status: 'error',
                message: 'Anda tidak memiliki akses untuk menghapus transaksi ini.',
                data: null
            });
        }

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

            res.status(200).json({ 
                status: 'success', 
                message: 'Transaksi berhasil dihapus!',
                data: null
            });
        });
    });
});

// 5. Endpoint GET: Ringkasan Saldo (Untuk Pie Chart & Kartu Saldo)
app.get('/ringkasan/:nim', authorizeOwnerOrAdmin, (req, res) => {
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
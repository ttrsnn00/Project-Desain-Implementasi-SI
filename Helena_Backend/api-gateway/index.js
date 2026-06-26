import 'dotenv/config';
import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import cors from 'cors';
import jwt from 'jsonwebtoken'; // Pindahkan import ke atas agar performa stabil

const app = express();
const PORT = process.env.PORT || 4000;

// Kunci stempel harus SAMA PERSIS dengan yang ada di Auth Service!
const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
    console.error('❌ JWT_SECRET tidak ditemukan di environment variables. Cek file .env!');
    process.exit(1);
}

// 1. CORS HARUS DI ATAS SEBELUM RUTE APAPUN
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));

// --- FUNGSI FORMATTER ERROR PROXY ---
// Mencegah Gateway mengirim halaman HTML 504 ke Flutter jika service di belakang mati
const proxyErrorHandler = (err, req, res) => {
    console.error(`[Gateway Error] Gagal menyambung ke rute: ${req.path}`, err.message);
    res.status(500).json({
        status: 'error',
        message: 'Layanan tidak dapat diakses saat ini. Silakan coba beberapa saat lagi.',
        data: null
    });
};

// --- FUNGSI SATPAM (MIDDLEWARE) UNTUK MENGECEK TIKET ---
const verifyToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // Format: "Bearer <token>"

    if (!token) {
        // Standarisasi format JSON: { status, message, data }
        return res.status(401).json({ 
            status: 'error', 
            message: 'Akses Ditolak. Anda tidak memiliki tiket (Token)!',
            data: null
        });
    }

    jwt.verify(token, JWT_SECRET, (err, decoded) => {
        if (err) {
            return res.status(403).json({ 
                status: 'error', 
                message: 'Tiket tidak sah atau sudah kedaluwarsa!',
                data: null
            });
        }
        // Jika tiket sah, persilakan lewat
        req.user = decoded; 
        next();
    });
};

// --- ROUTING API GATEWAY ---

// Rute Login & Register: TIDAK PERLU SATPAM (belum punya token saat ini)
app.use('/auth', createProxyMiddleware({ 
    target: 'http://auth-service:4001', 
    changeOrigin: true,
    onError: proxyErrorHandler // Tambahkan jaring pengaman error
}));

// Rute KHUSUS endpoint auth-service yang butuh login (mis. GET /users untuk admin).
// Path di sini ('/auth-protected/users' -> diteruskan sebagai '/users') supaya
// tidak bentrok dengan '/auth' di atas yang sengaja terbuka untuk login/register.
app.use('/auth-protected', verifyToken, createProxyMiddleware({
    target: 'http://auth-service:4001',
    changeOrigin: true,
    onError: proxyErrorHandler,
    pathRewrite: { '^/auth-protected': '' },
    on: {
        proxyReq: (proxyReq, req) => {
            proxyReq.setHeader('x-user-nim', req.user.nim);
            proxyReq.setHeader('x-user-role', req.user.role);
        }
    }
}));

// Rute Tagihan & Uang Saku: WAJIB DIJAGA SATPAM (`verifyToken`)
// Identitas user yang sudah terverifikasi diteruskan via header internal,
// supaya service di belakang bisa mengecek otorisasi level data (anti-IDOR)
// tanpa perlu verifikasi JWT lagi.
app.use('/kampus', verifyToken, createProxyMiddleware({ 
    target: 'http://campus-billing-service:4002', 
    changeOrigin: true,
    onError: proxyErrorHandler,
    on: {
        proxyReq: (proxyReq, req) => {
            proxyReq.setHeader('x-user-nim', req.user.nim);
            proxyReq.setHeader('x-user-role', req.user.role);
        }
    }
}));

app.use('/uang-saku', verifyToken, createProxyMiddleware({ 
    target: 'http://pocket-money-service:4003', 
    changeOrigin: true,
    onError: proxyErrorHandler,
    on: {
        proxyReq: (proxyReq, req) => {
            proxyReq.setHeader('x-user-nim', req.user.nim);
            proxyReq.setHeader('x-user-role', req.user.role);
        }
    }
}));

app.listen(PORT, '0.0.0.0', () => {
    console.log(`[API Gateway] Server berjalan di port ${PORT}...`);
});
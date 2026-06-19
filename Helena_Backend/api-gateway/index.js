import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import cors from 'cors';
import jwt from 'jsonwebtoken'; // Pindahkan import ke atas agar performa stabil

const app = express();
const PORT = 4000;

// Kunci stempel harus SAMA PERSIS dengan yang ada di Auth Service!
const JWT_SECRET = 'rahasia_super_helena_finance_2026';

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

// Rute Login: TIDAK PERLU SATPAM
app.use('/auth', createProxyMiddleware({ 
    target: 'http://auth-service:4001', 
    changeOrigin: true,
    onError: proxyErrorHandler // Tambahkan jaring pengaman error
}));

// Rute Tagihan & Uang Saku: WAJIB DIJAGA SATPAM (`verifyToken`)
app.use('/kampus', verifyToken, createProxyMiddleware({ 
    target: 'http://campus-billing-service:4002', 
    changeOrigin: true,
    onError: proxyErrorHandler
}));

app.use('/uang-saku', verifyToken, createProxyMiddleware({ 
    target: 'http://pocket-money-service:4003', 
    changeOrigin: true,
    onError: proxyErrorHandler
}));

app.listen(PORT, '0.0.0.0', () => {
    console.log(`[API Gateway] Server berjalan di port ${PORT}...`);
});
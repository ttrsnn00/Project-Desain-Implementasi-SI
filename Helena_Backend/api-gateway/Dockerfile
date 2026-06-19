# 1. Gunakan sistem operasi Linux ringan yang sudah terinstal Node.js
FROM node:18-alpine

# 2. Buat folder untuk menaruh kode kita di dalam Docker
WORKDIR /app

# 3. Salin file daftar pustaka (package.json) terlebih dahulu
COPY package*.json ./

# 4. Instal semua library yang dibutuhkan (express, http-proxy-middleware)
RUN npm install

# 5. Salin semua sisa kode kita (index.js) ke dalam Docker
COPY . .

# 6. Jalankan aplikasinya
CMD ["npm", "start"]
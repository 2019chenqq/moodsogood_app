const admin = require("firebase-admin");

// 初始化 Admin SDK (擁有繞過 Security Rules 的最高權限)
admin.initializeApp();

const db = admin.firestore();

module.exports = {
  admin,
  db,
};

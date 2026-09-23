# Katiba VPN

تطبيق Flutter عربي بواجهة Android لإدارة حساب Twist، مع الحفاظ على وظائف السكريبت الأصلي:

- تسجيل الدخول برقم الهاتف ورمز OTP.
- حفظ جلسة الدخول في Android Keystore عبر `flutter_secure_storage`.
- عرض الرصيد الحالي.
- جلب وتنفيذ المهام غير المكتملة.
- عرض سجل المعاملات وحساب الوحدات المسحوبة خلال الشهر.
- عرض الباقات المتاحة وتنفيذ السحب بعد تأكيد المستخدم.
- حذف فتح الموقع ورابط قناة Telegram بالكامل.

## البناء عبر krinry

```bash
cd katiba_vpn
krinry flutter init
git init
git add .
git commit -m "create Katiba VPN Flutter app"
gh repo create katiba-vpn --public --source=. --remote=origin --push
krinry flutter build apk --release
```

أو شغّل Workflow `Katiba VPN Build` من GitHub Actions واختر `apk` أو `appbundle`.

> التطبيق يتصل بنفس نقاط API الموجودة في السكريبت الأصلي. استخدمه فقط مع حسابك وبما يتوافق مع شروط الخدمة. لا تضع رموز الجلسات أو OTP داخل الكود أو GitHub.

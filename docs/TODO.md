# 待做

- [x] 个人信息页文字偏小：用户名、会员到期行、存储点阵行的字号整体调大一档
- [ ] 更换应用图标（icon）与启动图（当前为 Flutter 默认样式；
      图标在 android/app/src/main/res/ 各 mipmap，启动图在
      android/app/src/main/res/drawable/launch_background.xml，
      可考虑用 flutter_launcher_icons + flutter_native_splash 生成）
- [ ] 增加动画（页面切换/过渡等动效）
- [ ] 更换文件列表中文件夹与文件的图标（现为 Material outlined
      图标 + 主题色圆底，见 KindStyle）
- [x] 账号退出时加确认：点"退出"先弹框确认再清凭证（AlertDialog 已
      实现，手机上验证 OK）
- [x] 统一圆底图标的图案颜色：改为统一按底色亮度自动取黑/白
      （AppTheme.onColor），文件/云下载/主页顶栏图标同一条规则，
      手机上验证 OK

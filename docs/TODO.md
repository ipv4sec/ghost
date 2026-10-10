# 待做

- [x] 个人信息页文字偏小：用户名、会员到期行、存储点阵行的字号整体调大一档
- [ ] 更换应用图标（icon）与启动图（当前为 Flutter 默认样式；
      图标在 android/app/src/main/res/ 各 mipmap，启动图在
      android/app/src/main/res/drawable/launch_background.xml，
      可考虑用 flutter_launcher_icons + flutter_native_splash 生成）
- [ ] 增加动画（页面切换/过渡等动效）
- [ ] 更换文件列表中文件夹与文件的图标（现为 Material outlined
      图标 + 主题色圆底，见 KindStyle）
- [ ] 账号退出时加确认：点"退出"先弹框确认再清凭证（当前代码已有
      AlertDialog 确认，需在手机上确认效果，或按需调整形式）
- [ ] 统一圆底图标的图案颜色：当前黑白混用、风格不统一——文件页
      文件夹圆底图案色按底色亮度自动取黑/白（KindStyle.onAccent），
      同列表的文件圆底图案固定白色，云下载任务圆底图案也固定白色；
      需定一种规则统一（如全部固定白色，或全部按底色亮度自动黑/白）

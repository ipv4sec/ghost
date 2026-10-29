import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// 关于页
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          const SizedBox(height: 48),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_outlined,
                  color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('Ghost',
                style: TextStyle(
                    fontSize: 22, // varus 主内容字号
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('v0.1',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
          const SizedBox(height: 32),
          Divider(height: 1, color: AppTheme.divider),
          _row('应用简介', '115 网盘第三方客户端：文件浏览、'
              '视频在线播放。'),
          Divider(height: 1, color: AppTheme.divider),
          _row('数据来源', '基于 115 生活开放平台（open.115.com）'
              '提供的开放接口构建，账号授权数据保存在本机。'),
          Divider(height: 1, color: AppTheme.divider),
          _row('免责声明', '本应用为个人学习用途的第三方客户端，'
              '与 115 网盘无关联；请遵守平台使用条款。'),
          Divider(height: 1, color: AppTheme.divider),
        ],
      ),
    );
  }

  Widget _row(String title, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Text(content,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

interface Props {
  onClose: () => void;
}

export function PrivacyPolicy({ onClose }: Props) {
  return (
    <div className="modal-overlay" onClick={onClose} role="dialog" aria-label="Privacy Policy">
      <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 720, maxHeight: '85vh', overflow: 'auto' }}>
        <button className="modal-close" onClick={onClose} aria-label="閉じる">✕</button>
        <h2>プライバシーポリシー / Privacy Policy</h2>
        <p style={{ color: '#888', fontSize: 12 }}>最終更新日: 2025年3月25日</p>

        <h3>1. サービス概要</h3>
        <p>
          YouTube Niche Analyzer（以下「本サービス」）は、YouTube Data API v3 を利用して
          公開されている動画・チャンネルのメタデータを収集・分析し、YouTubeクリエイター向けに
          ニッチ分析ダッシュボードを提供する無料のオープンソースツールです。
        </p>

        <h3>2. 収集するデータ</h3>
        <p>本サービスは以下の<strong>公開データのみ</strong>を収集します：</p>
        <ul>
          <li>動画のメタデータ（タイトル、再生回数、高評価数、コメント数、投稿日、タグ、動画時間）</li>
          <li>チャンネルのメタデータ（チャンネル名、登録者数、総再生回数、動画数、開設日）</li>
        </ul>
        <p>本サービスは以下のデータを<strong>収集しません</strong>：</p>
        <ul>
          <li>ユーザーの個人情報（氏名、メールアドレス等）</li>
          <li>YouTubeユーザーの非公開データ</li>
          <li>Cookie やトラッキング情報</li>
          <li>ログイン情報（本サービスにログイン機能はありません）</li>
        </ul>

        <h3>3. YouTube API サービスの利用</h3>
        <p>
          本サービスは <a href="https://developers.google.com/youtube/terms/api-services-terms-of-service" target="_blank" rel="noopener noreferrer">YouTube API サービス利用規約</a> に準拠しています。
          また、<a href="https://policies.google.com/privacy" target="_blank" rel="noopener noreferrer">Google プライバシーポリシー</a> が適用されます。
        </p>

        <h3>4. データの利用目的</h3>
        <ul>
          <li>YouTubeのジャンル別需要・供給ギャップの分析</li>
          <li>競合密度・新規チャンネル成功率の算出</li>
          <li>トレンド分析とダッシュボードへの可視化表示</li>
        </ul>

        <h3>5. データの保存と管理</h3>
        <p>
          収集したデータは Supabase（PostgreSQL）に保存されます。
          データは統計分析の目的でのみ使用され、第三者への販売・提供は行いません。
        </p>

        <h3>6. データの共有</h3>
        <p>
          本サービスは収集したデータを第三者と共有しません。
          ダッシュボード上に表示される情報はすべて、YouTubeで一般公開されているデータの集計結果です。
        </p>

        <h3>7. ユーザーの権利</h3>
        <p>
          本サービスはユーザーの個人情報を収集しないため、個人データに関する削除・修正リクエストの対象はありません。
          YouTube API サービスへのアクセス許可の取り消しについては、
          <a href="https://security.google.com/settings/security/permissions" target="_blank" rel="noopener noreferrer">Google セキュリティ設定</a> から管理できます。
        </p>

        <h3>8. お問い合わせ</h3>
        <p>
          本ポリシーに関するお問い合わせは、
          <a href="https://github.com/s1-1985/yt-niche-analyzer/issues" target="_blank" rel="noopener noreferrer">GitHub Issues</a> よりご連絡ください。
        </p>
      </div>
    </div>
  );
}

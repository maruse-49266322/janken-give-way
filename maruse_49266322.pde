// 先端表現情報学基礎II の画像処理
// ビデオキャプチャライブラリをインポート
import processing.video.*;

// カメラ映像を扱うためのCaptureオブジェクトの宣言
Capture video;

// =============================================================
// --- 状態遷移（State）用定数 ---
// デジタルコンテンツのインタラクションを管理する状態駆動型の設計
// =============================================================
final int STATE_DRIVING   = 0; // 状態0: 通常の走行シーン
final int STATE_STANDBY   = 1; // 状態1: じゃんけん初期化（キャリブレーション・グーの手の登録待ち）
final int STATE_READY     = 2; // 状態2: じゃんけん勝負（Webカメラからのリアルタイム色・形状認識中）
final int STATE_RESULT    = 3; // 状態3: じゃんけん結果表示（勝敗の確定・対向車の挙動分岐）
final int STATE_GOAL      = 4; // 状態4: ゴール演出（目的地への接近、減速、停車シーン）

// 現在のゲーム内の状態を格納する変数（初期状態は通常走行）
int currentGameState = STATE_DRIVING;

// =============================================================
// --- 3Dドライブシミュレータの環境変数 ---
// 透視投影（パースペクティブ）を擬似的に表現するための幾何学パラメータ
// =============================================================
float speed = 5.0;            // 自車の走行速度（背景や道路の更新速度に影響）
float lineOffset = 0;         // 道路の中央線・白線を動かして進路を表現するための位相オフセット
float steerAngle = 0;         // プレイヤーのハンドル操舵角（消失点の左右移動に使用）
float roadWidthPhase = 0;     // 道路のうねり・道幅の変化を制御する三角関数の位相
float baseRoadWidth;          // 計算によって動的に決定される現在の道路の幅

int carState = 0;             // 対向車の挙動ステート（0:出現前, 1:対抗先行, 2:自車先行, 3:通過後）
float carParam = 0.0;         // 対向車の奥行き位置（0.0:遠景（消失点） ～ 1.0:近景（画面手前））
float carX, carY;             // 対向車の画面上における描画中心座標
float carW, carH;             // 対向車の遠近法に基づく描画サイズ（手前に来るほど拡大）
boolean isForcedStop = false; // ボトルネック（狭い道）での強制停車フラグ
int hmiChoice = 0;            // HMI（ヒューマンマシンインタフェース）の選択判定結果（1:譲る, 2:先行, 3:あいこ再試行）

float seaWaveOffset = 0;      // 画面左側の海面の波アニメーション用時間オフセット
float myVehicleXOffset = 0;   // 道幅減少時に自車（カメラ視野）を左に滑らかに寄せるための補間オフセット

// =============================================================
// --- じゃんけん・色認識（画像処理）システムの変数 ---
// =============================================================
int guBasePixels = 0;         // キャリブレーション時に登録された「グー（肌色）」の基準ピクセル数
int matchCount = 0;           // 遭遇した対向車との対戦回数カウント (最大3回でゴールへ)
int userWins = 0;             // プレイヤーの累積勝利数（エンディングのセリフ分岐に使用）
String userHand = "UNKNOWN";  // 認識されたユーザーの手（"ROCK", "GOLD_LICENSE" などの識別子）
String sysHand = "UNKNOWN";   // NPC（対向車）のランダムな手（"ROCK", "SCISSORS", "PAPER"）
String roundResult = "";      // 現在のラウンドの勝敗結果文字列（"YOU WIN!", "YOU LOSE...", "DRAW"）

// 【講義の基本要素】特定の閾値に合致したピクセル数を格納するカウンタ
int skinPixelsCount = 0;      // 画像全体から検出された肌色ピクセルの総数
int countYellow = 0;          // 画像全体から検出された特定黄色ピクセルの総数
int countGreen = 0;           // 画像全体から検出された特定緑色ピクセルの総数
int countBlue = 0;            // 画像全体から検出された特定青色ピクセルの総数

// =============================================================
// 【講義重要パート】HSB（HSV）カラー空間における領域分割の閾値設定
// RGB空間は照明変動に弱いため、色相（H）、彩度（S）、明度（B）に分離して閾値を設定する
// =============================================================
// 黄色（ゴールド免許判定用）: 実測値（H:58, S:47, B:56）からマージンを考慮して設計
float yellowHueMin = 48;   float yellowHueMax = 68;   // 色相の範囲：黄色のコア領域を±10で指定
float yellowSatMin = 35;   float yellowSatMax = 75;   // 彩度の範囲：ある程度の鮮やかさを持つ領域
float yellowBriMin = 40;   float yellowBriMax = 85;   // 明度の範囲：室内光の陰影に対応

// 青色（一般・優良免許判定用）
float blueHueMin = 195;    float blueHueMax = 230;    // 色相の範囲：青〜水色
float blueSatMin = 25;     float blueSatMax = 60;     // 彩度の範囲
float blueBriMin = 35;     float blueBriMax = 95;     // 明度の範囲

// 緑色（新規免許・初心者マーク判定用）: 実測値（H:84, S:44, B:43）から設計
float greenHueMin = 72;    float greenHueMax = 96;    // 色相の範囲：黄緑から深い緑の手前までをカバー
float greenSatMin = 30;    float greenSatMax = 70;    // 彩度の範囲
float greenBriMin = 30;    float greenBriMax = 75;    // 明度の範囲：実測の43という低明度をカバーする下限設定

PFont jpFont;                 // 日本語ガイダンスや文字を描画するためのフォントオブジェクト

// --- ゴール（我が家出現）演出用変数 ---
float goalParam = 0.0;        // 家の接近度合いを表す幾何パラメータ（0.0:遠景 ～ 1.0:手前停車）
float goalFade = 0;           // 停車後にリザルト画面を滑らかにフェードインさせるための不透明度（0〜255）

// --- キーボード入力を1フレームに1回だけ検知するためのフラグ（チャタリング防止） ---
boolean lastKeyPressed = false;

// =============================================================
// 初期設定関数（アプリケーション起動時に1度だけ実行）
// =============================================================
void setup() {
  size(800, 600);                     // 画面サイズを横800、縦600ピクセルに設定（ウィンドウ生成）
  video = new Capture(this, 640, 480);// Webカメラから 640x480 の解像度でキャプチャするインスタンスを生成
  video.start();                      // ビデオキャプチャ（映像ストリームの取得）を開始

  jpFont = createFont("MS Gothic", 24);// 描画システムに「MS ゴシック」サイズ24を割り当て（日本語崩れ防止）
  textFont(jpFont);                   // 作成したフォントをアクティブに設定
}

// =============================================================
// メイン描画ループ関数（毎秒60フレームで周期的に実行される）
// =============================================================
void draw() {
  // カメラのハードウェアバッファに新しいフレームが到着しているかを確認
  if (video.available()) {
    video.read();                     // 到着していれば新しいフレームをメモリ上のピクセル配列に読み込む
  }

  // -------------------------------------------------------------
  // 1. 背景・道路・地形・コックピットのグラフィック描画処理
  // -------------------------------------------------------------
  background(100, 110, 130);          // 画面全体を空の色（くすんだ青灰色）で塗りつぶし（バッファのクリア）

  // キーボードによるハンドル操作（フリーズ状態[hmiChoice==3]やゴール時は操作無効）
  if (keyPressed && hmiChoice != 3 && currentGameState != STATE_GOAL) {
    if (keyCode == LEFT)       steerAngle -= 0.05; // 左矢印キーで操舵角をマイナス（左）に傾ける
    else if (keyCode == RIGHT) steerAngle += 0.05; // 右矢印キーで操舵角をプラス（右）に傾ける
  } else if (hmiChoice != 3) {
    steerAngle *= 0.9;                // キーを離している時は、0.9を乗算してセンター（0）へ滑らかに戻す（復元力）
  }
  steerAngle = constrain(steerAngle, -HALF_PI, HALF_PI); // 操舵角が過剰にならないよう ±90度(-1.57〜1.57)に制限

  float horizonY = height * 0.45;     // 遠近法の「地平線（消失点の高さ）」を画面上部から45%の位置に定義
  fill(20, 40, 50);                   // 大地のベースとなる暗い緑灰色の塗りを設定
  noStroke();                         // 輪郭線を描画しない
  rect(0, horizonY, width, height - horizonY); // 地平線から画面最下部まで大地を描画

  // 自車が移動中かつイベント中でない場合、道路のシミュレーション位相を進める
  if (!isForcedStop && hmiChoice != 3 && currentGameState != STATE_GOAL) {
    roadWidthPhase += speed * 0.0025; // スピードに比例した速度で位相を前進させ、道路の遠近感を動かす
  }

  // サイン関数を用いて、道路が広くなったり狭くなったりするボトルネック現象を周期的に生成
  float sinVal = sin(roadWidthPhase);
  float transformedSin;
  if (sinVal < -0.6) {
    // サイン波が特定の閾値（-0.6）より小さい時、数式を歪めて「急激に道が狭くなるボトルネック」を誇張表現
    transformedSin = map(sinVal, -1.0, -0.6, -1.0, 0.7);
    transformedSin = -1.0 + 1.7 * pow((transformedSin + 1.0) / 1.7, 5.0); // 5乗のカーブで急峻に変化させる
  } else {
    transformedSin = map(sinVal, -0.6, 1.0, 0.7, 1.0); // それ以外の領域はなだらかに広い道を維持
  }

  // 現在の道幅を計算（ゴール状態なら滑らかに幅300に収束させ、通常時は210〜500の間で可変）
  if (currentGameState == STATE_GOAL) {
    baseRoadWidth = lerp(baseRoadWidth, 300, 0.05); // 線形補間（lerp）を用いて現在の道幅を5%ずつターゲットに近づける
  } else {
    baseRoadWidth = map(transformedSin, -1, 1, 210, 500); // 歪めたサイン波を実際のピクセル道幅（210〜500）にマッピング
  }

  // 道が狭くなった時に自車の位置を視覚的に左に寄せるためのオフセット計算
  float targetXOffset = map(constrain(baseRoadWidth, 210, 380), 210, 380, 0, 130);
  if (hmiChoice != 3) {
    myVehicleXOffset = lerp(myVehicleXOffset, targetXOffset, 0.08); // 8%ずつの時定数で滑らかにカメラワークを移動
  }

  // 消失点のX座標を決定（ハンドルの操舵角に応じて左右に最大100ピクセルシフトし、カーブを表現）
  float vpX = width / 2 + (steerAngle * 100);

  // 【ステート遷移トリガーA】3回のインタラクションが完了し、かつ道が狭くなった瞬間にゴールステートへ突入
  if (matchCount >= 3 && baseRoadWidth < 380 && transformedSin < 0 && currentGameState == STATE_DRIVING) {
    currentGameState = STATE_GOAL;    // 状態をゴール演出に移行
    goalParam = 0.0;                  // 家の距離をリセット
    goalFade = 0;                     // フェードインの不透明度をクリア
  }
  // 【ステート遷移トリガーB】通常のボトルネック（対戦3回未満）に突入した時、車を強制停止させてじゃんけんを開始
  else if (baseRoadWidth < 380 && transformedSin < 0 && carState == 0 && matchCount < 3) {
    carState = 1;                     // 対向車の出現フラグをON
    isForcedStop = true;              // 自車の強制停車フラグをON
    speed = 0;                        // 自車の速度をゼロにする
    carParam = 0.0;                   // 対向車を遠く（消失点）に配置
    hmiChoice = 0;                    // HMIの選択肢を初期化
    currentGameState = STATE_STANDBY; // 画像認識システムをキャリブレーション待ち（状態1）へ移行
  }

  // --- 地形描画：左側の海 ---
  fill(15, 45, 75);                   // 深い海の青を設定
  beginShape();                       // 自由形状の描画開始
  vertex(0, horizonY);                // 左上の頂点（地平線の左端）
  vertex(vpX - 10, horizonY);         // 右上の頂点（消失点のわずかに左）
  vertex(width/2 - baseRoadWidth + myVehicleXOffset, height); // 右下の頂点（道路の左エッジの画面最下部）
  vertex(0, height);                  // 左下の頂点
  endShape(CLOSE);                    // 形状を閉じて描画

  // 海の波アニメーション処理
  if (hmiChoice != 3 && currentGameState != STATE_GOAL) {
    seaWaveOffset += 0.03 + (speed * 0.005); // 走行速度に応じて波の動く速さを変える
  }
  for (int waveIdx = 0; waveIdx < 3; waveIdx++) { // 3層の波を重ねて奥行きと複雑な動きを表現
    fill(25 + waveIdx * 15, 65 + waveIdx * 15, 105 + waveIdx * 20, 180); // 各層で色と透明度をずらす
    beginShape();
    vertex(0, horizonY);
    vertex(vpX - 10, horizonY);
    // 消失点から画面左端に向かって20ピクセル刻みで波の細分化頂点を配置（サイン波による幾何変形）
    for (float x = vpX - 10; x >= 0; x -= 20) {
      float yFactor = map(x, vpX - 10, 0, 0, 1); // 消失点に近いほど波を小さく、手前に来るほど大きくするための係数
      float waveY = map(yFactor, 0, 1, horizonY, height); // Y座標を割り出し
      float edgeX = map(waveY, horizonY, height, vpX - 10, width/2 - baseRoadWidth + myVehicleXOffset); // 道路境界のX座標
      float waveOffset = sin(x * 0.05 + seaWaveOffset + waveIdx * TWO_PI / 3) * (5 + yFactor * 25); // 波のうねりをサイン関数で計算
      vertex(edgeX + waveOffset, waveY); // うねりを加えた頂点を追加
    }
    vertex(0, height);
    endShape(CLOSE);
  }

  // --- 地形描画：右側の崖 ---
  // ゴール時は、家が建つスペースを空けるために崖を右側へ滑らかにシフト（cliffOffset）させる
  float cliffOffset = (currentGameState == STATE_GOAL) ? map(goalParam, 0, 1, 0, 200) : 0;
  fill(50, 45, 40);                   // 岩肌の茶褐色を設定
  beginShape();
  vertex(vpX + 10, horizonY);         // 消失点の右側からスタート
  vertex(width, horizonY - 150);      // 画面右の遠景の山なみ
  vertex(width/2 + baseRoadWidth + myVehicleXOffset + 400 + cliffOffset, height - 300); // 手前の崖エッジ1
  vertex(width/2 + baseRoadWidth + myVehicleXOffset + cliffOffset, height);             // 道路の右エッジ（画面最下部）
  endShape(CLOSE);

  // 崖のサイド部分（立体感を出すための暗い面）の描画
  fill(35, 30, 28);                   // より暗い影の茶色
  beginShape();
  vertex(vpX + 10, horizonY);
  vertex(vpX + 80, horizonY);
  vertex(width/2 + baseRoadWidth + myVehicleXOffset + 100 + cliffOffset, height);
  vertex(width/2 + baseRoadWidth + myVehicleXOffset + cliffOffset, height);
  endShape(CLOSE);

  // --- 中央の道路の路面描画 ---
  fill(70);                           // アスファルトの灰色を設定
  beginShape();
  vertex(vpX - 10, horizonY);         // 消失点左エッジ
  vertex(vpX + 10, horizonY);         // 消失点右エッジ
  vertex(width/2 + baseRoadWidth + myVehicleXOffset, height); // 手前右エッジ
  vertex(width/2 - baseRoadWidth + myVehicleXOffset, height); // 手前左エッジ
  endShape(CLOSE);

  // 道路上の白線・中央線の流れるアニメーション計算
  if (hmiChoice != 3 && speed > 0) {
    lineOffset += speed;              // スピードに応じて線を下方向に動かす
    if (lineOffset > 40) lineOffset = 0; // 一定距離流れたらリセットしてループ
  }

  // 疑似3D空間を表現するため、地平線から手前にかけてループを回し、路面標示を遠近法（パース）に基づいて分割描画
  for (float i = 0; i < 1; i += 0.05) {
    // 【画像処理・3Dグラフィックス概念】非線形マッピング（2乗）を用いて、手前ほど描画間隔が広くなるようにパースを強調
    float y1 = lerp(horizonY, height, pow(i, 2));
    float y2 = lerp(horizonY, height, pow(i + 0.02, 2));
    
    // アニメーションオフセットを現在のY座標のパースに合わせてスケーリング
    y1 += lineOffset * (y1 - horizonY) * 0.01;
    y2 += lineOffset * (y2 - horizonY) * 0.01;

    // 画面外に出てしまった線のインデックスは描画をスキップ
    if (y1 > height || y2 > height || y1 < horizonY) continue;

    // 現在のY位置における、道路の左エッジ・右エッジ・中央線のX座標を線形マッピングで算出
    float xl1 = map(y1, horizonY, height, vpX - 10, width/2 - baseRoadWidth + myVehicleXOffset);
    float xl2 = map(y2, horizonY, height, vpX - 10, width/2 - baseRoadWidth + myVehicleXOffset);
    float xr1 = map(y1, horizonY, height, vpX + 10, width/2 + baseRoadWidth + myVehicleXOffset);
    float xr2 = map(y2, horizonY, height, vpX + 10, width/2 + baseRoadWidth + myVehicleXOffset);
    float xc1 = map(y1, horizonY, height, vpX, width / 2 + myVehicleXOffset);
    float xc2 = map(y2, horizonY, height, vpX, width / 2 + myVehicleXOffset);

    // 道幅が広いとき（片側1車線以上あるとき）、中央に黄色のセンターラインを描画
    if (baseRoadWidth >= 350 && int(i * 100) % 2 == 0) {
      stroke(255, 200, 0);            // 警戒色の黄色
      makeStrokeWeightFix(4);         // 線の太さを固定
      line(xc1, y1, xc2, y2);         // 中央線を描画
    }
    // 道路左端の破線（白線）の描画
    if (int(i * 100) % 2 == 0) {
      stroke(200);                    // 薄い灰色（白線）
      makeStrokeWeightFix(map(y1, horizonY, height, 1, 6)); // 遠近感に基づき、手前に来るほど線を太くする
      // 左エッジから少し内側に入ったキャッツアイ・縁石風の路面標示をシミュレート
      line(xl1, y1, xl1 - map(y1, horizonY, height, 2, 20), y1 + map(y1, horizonY, height, 5, 40));
    }
    // 道路右端の外側（崖の手前）に並ぶ、安全のための防護柵・ポールを擬似的に描画
    if (int(i * 100) % 3 == 0 && currentGameState != STATE_GOAL) {
      stroke(20, 15, 15);             // ポールの影・支柱の色
      makeStrokeWeightFix(map(y1, horizonY, height, 1, 8)); // 遠近感に基づき手前ほど太く
      line(xr1 + map(y1, horizonY, height, 5, 80), y1, xr2 + map(y2, horizonY, height, 5, 80), y2 - map(y1, horizonY, height, 10, 100));
    }
  }
  // 道路の左エッジおよび右エッジの静的な境界線を引く
  stroke(180);
  makeStrokeWeightFix(2);
  line(vpX - 10, horizonY, width/2 - baseRoadWidth + myVehicleXOffset - 40, height + 30);
  stroke(255);
  makeStrokeWeightFix(3);
  line(vpX + 10, horizonY, width/2 + baseRoadWidth + myVehicleXOffset, height);

  // -------------------------------------------------------------
  // 2. 【核心画像処理パート】じゃんけん制御・カラー認識アルゴリズム
  // -------------------------------------------------------------
  // 特定のインタラクションステートの時のみ、膨大なCPU負荷を避けるためにWebカメラ画像を走査する
  if (currentGameState == STATE_STANDBY || currentGameState == STATE_READY || currentGameState == STATE_RESULT) {
    video.loadPixels();               // Webカメラの最新フレームのピクセルデータを pixels[] 配列に展開（必須画像処理関数）
    
    // 【画像処理概念】一時的にカラーモードを「HSB空間（円錐モデル）」に変換。
    // 色相を360度、彩度を100%、明度を100%のスケールで定義し、直感的な閾値による色領域抽出（カラーセグメンテーション）を行う。
    colorMode(HSB, 360, 100, 100);
    
    // 毎フレームの走査を始める前に、ピクセル数の集計カウンタをゼロクリア
    skinPixelsCount = 0;
    countYellow = 0;
    countGreen = 0;
    countBlue = 0;

    // 【画像処理の基本手法：画素走査ループ】ネストされた2重ループにより、640x480画素の全ピクセルを1つずつ全探索
    for (int cx = 0; cx < video.width; cx++) {
      for (int cy = 0; cy < video.height; cy++) {
        int loc = cx + cy * video.width; // 2次元座標（cx, cy）から1次元の配列インデックス（loc）への線形変換式
        color c = video.pixels[loc];    // 指定位置のピクセル（色情報）を1つ抽出

        // 抽出したカラーデータから、HSB空間における3つの独立した特徴量を個別に取得
        float h = hue(c);               // 色相成分（0〜360度：色みの種類）
        float s = saturation(c);        // 彩度成分（0〜100%：色の鮮やかさ）
        float b = brightness(c);        // 明度成分（0〜100%：色の明るさ）

        // --- A. 肌色領域のセグメンテーション（通常のじゃんけん用） ---
        // 色相が赤〜橙の領域（0〜28度、または330〜360度付近）、かつ彩度・明度がある程度高い領域を人間の皮膚として抽出
        if ((h >= 0 && h <= 28 || h >= 330) && (s >= 15 && s <= 85) && (b >= 25)) {
          skinPixelsCount++;            // 条件に合致した肌色画素数をインクリメント
        } 
        // --- B. 黄色領域のセグメンテーション（ゴールド免許の検出） ---
        // 事前にユーザーがクリックして取得した正確な実測パラメータ（H:58）に基づき設定された範囲で判定
        // 【バグ修正済み】：s >= yellowSatMin && s <= yellowSatMax のように、上限側を正しく「<=」で評価
        else if (h >= yellowHueMin && h <= yellowHueMax && s >= yellowSatMin && s <= yellowSatMax && b >= yellowBriMin && b <= yellowBriMax) {
          countYellow++;                // 条件に合致した黄色画素数をインクリメント
        }
        // --- C. 緑色領域のセグメンテーション（グリーン免許の検出） ---
        // 実測値（H:84, S:44, B:43）に適合する閾値。蛍光灯下の暗い緑色カードも正確に捉える
        // 【バグ修正済み】：彩度上限の不等号を「<=」へ修正し、ノイズ以外の純粋な緑を捉える仕様へ
        else if (h >= greenHueMin && h <= greenHueMax && s >= greenSatMin && s <= greenSatMax && b >= greenBriMin && b <= greenBriMax) {
          countGreen++;                 // 条件に合致した緑色画素数をインクリメント
        }
        // --- D. 青色領域のセグメンテーション（ブルー免許の検出） ---
        else if (h >= blueHueMin && h <= blueHueMax && s >= blueSatMin && s <= blueSatMax && b >= blueBriMin && b <= blueBriMax) {
          countBlue++;                  // 条件に合致した青色画素数をインクリメント
        }
      }
    }
    // 【重要】ピクセル走査が終わったら、描画システム（背景やHMI車など）への悪影響を防ぐため、カラーモードを標準の「RGB」空間へ即座に復帰
    colorMode(RGB, 255, 255, 255);
  }

  // =============================================================
  // 対向車の挙動アニメーションロジック（HMIインタラクションの結果に応じる）
  // =============================================================
  if (carState >= 1 && currentGameState != STATE_GOAL) {
    if (hmiChoice == 1 && carState == 1) { // 挙動パターン1: プレイヤーの負け、またはグリーン免許提示
      carParam += 0.012;              // 対向車がグングン手前に進んでくる（接近）
      if (carParam > 1.0) {            // 画面最手前（1.0）を越えたら、自車の横を通り過ぎたとみなす
        carState = 3;                 // 対向車ステートを「通過完了（3）」にする
        isForcedStop = false;         // 自車のホールドを解除
        speed = 3.0;                  // 自車を低速で自動再発進させる
        currentGameState = STATE_DRIVING; // 通常の走行ステートへ復帰
      }
    } else if (hmiChoice == 2) { // 挙動パターン2: プレイヤーの勝ち、またはゴールド免許提示
      if (carState == 1) {
        carParam = 0.15;              // 対向車は遠く（0.15の位置）で完全に停止して道を譲る
        if (baseRoadWidth >= 320 && transformedSin > 0) carState = 2; // ボトルネックを抜け、道幅が広がり始めたら自車が追い抜きをかける
      } else if (carState == 2) {
        carParam += 0.012 + (speed * 0.001); // 自車の前進スピードに合わせて対向車を後方へ流す（擬似的な相対速度表現）
        if (carParam > 1.0) {
          carState = 3;
          currentGameState = STATE_DRIVING; // 通過後、通常走行へ
        }
      }
    } else if (hmiChoice == 0 || hmiChoice == 3) { // 挙動パターン3: あいこ、または認識待機状態
      carParam = 0.15;                // 対向車は遠景のすれ違い手前位置でじっと待機（フリーズ）
    }

    // 対向車の座標計算（奥行きパラメータ carParam の2乗を用いて、手前に来るほど急激に加速・拡大して見えるパース効果を実装）
    carY = lerp(horizonY, height, pow(carParam, 2));
    float currentRoadRightX = map(carY, horizonY, height, vpX + 10, width/2 + baseRoadWidth + myVehicleXOffset);
    float currentCenterLineX = map(carY, horizonY, height, vpX, width/2 + myVehicleXOffset);

    // 道幅に応じて対向車が中央に寄るか、左車線（対向視点での右）に避けるかをマッピング
    float targetCarX = (baseRoadWidth < 300) ? currentCenterLineX : lerp(currentCenterLineX, currentRoadRightX, 0.4);
    carX = lerp(currentCenterLineX, targetCarX, carParam);

    // 遠近法（パースペクティブ）に基づき、車の描画幅（W）と高さ（H）を線形マッピングでリアルに拡大
    carW = map(carY, horizonY, height, 5, 220);
    carH = map(carY, horizonY, height, 4, 160);

    // 車体の3D的立体感を2Dポリゴン（beginShape）の組み合わせで擬似表現するための各パーツの頂点座標計算
    float fLeft   = carX - carW/2;    // フロント（前面）の左端
    float fRight  = carX + carW/2;    // フロントの右端
    float fBottom = carY;             // フロントの下端（接地線）
    float fTop    = carY - carH;      // フロントの上端（ルーフ）
    float rLeft   = lerp(fLeft, vpX, 0.25);   // リア（奥行き）の左端座標を消失点方向へ絞り込む
    float rRight  = lerp(fRight, vpX, 0.25);  // リアの右端座標
    float rTop    = lerp(fTop, horizonY, 0.15); // リアのルーフ高さ
    float rBottomX = lerp(fRight, vpX, 0.25);
    float rBottomY = lerp(fBottom, horizonY, 0.15);

    // 一定の距離（画面下部76%）に到達するまで対向車を詳細にレンダリング
    if (carY < height * 0.76) {
      noStroke();
      fill(0, 60);
      ellipse(carX, carY, carW * 1.4, carH * 0.15); // 車体下部の「ドロップシャドウ（影）」
      
      fill(120, 20, 20);              // 車体側面の暗い赤（3Dの影を表現）
      beginShape();
      vertex(fRight, fBottom);
      vertex(fRight, fTop);
      vertex(rRight, rTop);
      vertex(rBottomX, rBottomY);
      endShape(CLOSE);
      
      fill(210, 60, 60);              // ルーフ（天井）のやや明るい赤
      beginShape();
      vertex(fLeft, fTop);
      vertex(fRight, fTop);
      vertex(rRight, rTop);
      vertex(rLeft, rTop);
      endShape(CLOSE);
      
      fill(170, 35, 35);              // 車体正面（フロントマスク）の基本となる赤
      rect(fLeft, fTop, carW, carH, carW*0.05); // 角丸長方形でフロントをレンダリング
      
      fill(40, 50, 65);               // フロントガラスの紺色
      beginShape();
      vertex(fLeft + carW * 0.08, fTop + carH * 0.1);
      vertex(fRight - carW * 0.08, fTop + carH * 0.1);
      vertex(fRight - carW * 0.05, fTop + carH * 0.48);
      vertex(fLeft + carW * 0.05, fTop + carH * 0.48);
      endShape(CLOSE);

      // あいこフリーズ状態[hmiChoice==3]の時は、パッシング（ヘッドライトの点滅）をアニメーションさせてドライバーに意思伝達（HMI効果）
      if ((hmiChoice == 0 || hmiChoice == 3) && frameCount % 30 < 15) fill(255, 255, 230); // ライト点灯（明るい黄色）
      else fill(255, 255, 150);                                                           // ライト通常
      ellipse(fLeft + carW*0.18, fTop + carH*0.72, carW*0.16, carH*0.12);  // 左ヘッドライト
      ellipse(fRight - carW*0.18, fTop + carH*0.72, carW*0.16, carH*0.12); // 右ヘッドライト
      
      fill(20);                       // フロントグリルの黒
      rect(carX - carW*0.22, fTop + carH*0.68, carW*0.44, carH*0.12, carW*0.02);
    }
  }

  // 対向車が完全に通り過ぎ、ボトルネックのうねりが解消（>0.95）されたら、対向車システム全体を初期状態（0）へリセット
  if (carState == 3 && transformedSin > 0.95) {
    carState = 0;
    hmiChoice = 0;
  }

  // -------------------------------------------------------------
  // 3. 右側に家（目的地・我が家）を3Dパース投影して描画
  // -------------------------------------------------------------
  if (currentGameState == STATE_GOAL) {
    goalParam = min(goalParam + (speed * 0.0015), 1.0); // ゴール内での前進処理（最大1.0でストップ）
    speed = max(5.0 * (1.0 - goalParam), 0.0);       // 【重要HMI自動制御】家に接近するにつれて、自動で減速し、手前で速度ゼロにする自動ブレーキシステム

    // 家のY座標をパース（2乗）に基づいて遠くから手前にダイナミックに配置
    float houseY = lerp(horizonY, height * 1.2, pow(goalParam, 2));
    float roadRightEdgeX = map(houseY, horizonY, height, vpX + 10, width/2 + baseRoadWidth + myVehicleXOffset);
    float houseX = roadRightEdgeX + map(houseY, horizonY, height, 10, 180); // 道路の右側に沿って配置

    // 遠近法に基づき、家の大きさをリアルにマッピング
    float houseW = map(houseY, horizonY, height, 8, 350);
    float houseH = map(houseY, horizonY, height, 6, 280);

    // 家のポリゴン用基本座標
    float hLeft   = houseX - houseW/2;
    float hRight  = houseX + houseW/2;
    float hBottom = houseY;
    float hTop    = houseY - houseH;

    // 消失点（vpX）に対する奥行き計算を行い、家を3次元的な立体構造物としてレンダリングするためのリア座標を抽出
    float hDepthLeft  = lerp(hLeft, vpX, 0.2);
    float hDepthRight = lerp(hRight, vpX, 0.2);
    float hDepthTop   = lerp(hTop, horizonY, 0.12);
    float hDepthBottomY = lerp(hBottom, horizonY, 0.12);

    if (houseY < height * 1.5) {
      noStroke();
      fill(0, 45);
      ellipse(houseX, houseY, houseW * 1.3, houseH * 0.15); // 建物の影

      fill(160, 140, 120);
      beginShape(); // 左側面の壁（奥行き面）
      vertex(hLeft, hBottom);
      vertex(hLeft, hTop);
      vertex(hDepthLeft, hDepthTop);
      vertex(hDepthLeft, hDepthBottomY);
      endShape(CLOSE);

      fill(235, 225, 210);
      rect(hLeft, hTop, houseW, houseH); // 正面の壁（アイボリーホワイト）

      // --- 三角屋根の描画（パースペクティブの方向を正しい反転に修正反映） ---
      float roofPeakX = houseX;
      float roofPeakY = hTop - (houseH * 0.35); // 屋根の頂点高さ
      
      float roofDepthPeakX = lerp(roofPeakX, vpX, 0.2); // 消失点へ向かう奥行きの屋根頂点
      float roofDepthPeakY = lerp(roofPeakY, horizonY, 0.12);

      // 【修正反映】陰影表現の反転。正面側をやや暗い赤、消失点へ向かう側面を明るい赤にして立体感を適正化
      fill(140, 35, 35); // 少し暗い赤（正面屋根）
      beginShape();
      vertex(hLeft - houseW*0.05, hTop);
      vertex(roofPeakX, roofPeakY);
      vertex(hRight + houseW*0.05, hTop);
      endShape(CLOSE);

      fill(180, 50, 50); // 明るい赤（奥行きの側面屋根）
      beginShape();
      vertex(hLeft - houseW*0.05, hTop);
      vertex(roofPeakX, roofPeakY);
      vertex(roofDepthPeakX, roofDepthPeakY);
      vertex(hDepthLeft, hDepthTop);
      endShape(CLOSE);

      // 家が一定以上近づいて大きくなったら、ドアや窓の詳細パーツを2D描画（ディテール・カリング）
      if (houseW > 40) {
        fill(100, 60, 30);
        rect(houseX - houseW*0.1, hBottom - houseH*0.4, houseW*0.2, houseH*0.4); // 玄関ドア
        fill(150, 200, 240);
        rect(hLeft + houseW*0.15, hTop + houseH*0.2, houseW*0.2, houseH*0.25); // 左の窓（ガラスの青）
        rect(hRight - houseW*0.35, hTop + houseH*0.2, houseW*0.2, houseH*0.25); // 右の窓
      }
    }
  }

  // -------------------------------------------------------------
  // 4. 車両コックピット・インパネ計器類の描画（オーバーレイUI）
  // -------------------------------------------------------------
  noStroke();
  fill(30);                           // ダッシュボードの黒に近い暗灰色
  beginShape();
  vertex(0, height * 0.7);            // 画面の下部30%をコックピット領域として遮蔽
  vertex(width, height * 0.7);
  vertex(width, height);
  vertex(0, height);
  endShape(CLOSE);
  
  fill(22);                           // フロントウィンドウ右ピラーの暗い影
  beginShape();
  vertex(width * 0.78, height * 0.7);
  vertex(width, height * 0.55);
  vertex(width, height);
  vertex(width * 0.75, height);
  endShape(CLOSE);
  
  fill(28);                           // Aピラー本体の描画
  beginShape();
  vertex(width * 0.76, height * 0.7);
  vertex(width * 0.79, height * 0.7);
  vertex(width, 0);
  vertex(width * 0.94, 0);
  endShape(CLOSE);

  fill(15);                           // メーターパネル（インパネカウル）の半円
  arc(width / 2, height * 0.75, 220, 120, PI, TWO_PI);
  
  stroke(0, 255, 0);                  // スピードメーターのサイバーグリーン
  makeStrokeWeightFix(2);
  noFill();
  arc(width / 2 - 50, height * 0.73, 60, 60, PI, TWO_PI);

  // スピードメーターの指針計算（現在の speed を角度にコンバートして線描画）
  float speedAngle = map(speed, 0, 15, PI, TWO_PI);
  line(width / 2 - 50, height * 0.73, width / 2 - 50 + cos(speedAngle)*25, height * 0.73 + sin(speedAngle)*25);

  stroke(255, 150, 0);                // タコメーター（エンジン回転数）のオレンジ
  arc(width / 2 + 50, height * 0.73, 60, 60, PI, TWO_PI);
  
  // 停車時、走行時、フリーズ時でアイドリングRPMのベース挙動を切り替える
  float baseRpm = (isForcedStop || currentGameState == STATE_GOAL) ? 1.0 : 3.0;
  if (hmiChoice == 3 || speed == 0) baseRpm = 0.0;
  // エンジンが生きていれば random(-0.05, 0.05) による微細な針の「振動」を加え、臨場感を付加
  float rpmAngle = map(baseRpm + (baseRpm > 0 ? random(-0.05, 0.05) : 0), 0, 8, PI, TWO_PI);
  line(width / 2 + 50, height * 0.73, width / 2 + 50 + cos(rpmAngle)*25, height * 0.73 + sin(rpmAngle)*25);

  // マトリックス変換を用いて、プレイヤーがキー入力した操舵角 steerAngle と同期して物理回転するステアリング（ハンドル）を2D描画
  pushMatrix();                       // 現在の座標系マトリックスをスタックに保存
  translate(width / 2, height * 0.82);// 回転の中心点をハンドルのボス位置に移動
  rotate(steerAngle);                 // 座標系を指定角度だけ回転
  noFill();
  stroke(50);
  makeStrokeWeightFix(18);            // ハンドルの外周（グリップの太さ18）
  ellipse(0, 0, 180, 180);
  stroke(100);
  makeStrokeWeightFix(2);
  ellipse(0, 0, 170, 170);            // ホーンリングのメッキライン
  stroke(40);
  makeStrokeWeightFix(16);
  line(-85, 0, 85, 0);                // ハンドルの水平スポーク
  line(0, 0, 0, 85);                  // ハンドルの垂直下部スポーク
  fill(20);
  noStroke();
  ellipse(0, 0, 45, 45);              // 中央のセンターキャップ（エンブレム部）
  popMatrix();                        // 座標系を元に戻す（これ以降の描画が回転しないようにする）

  // -------------------------------------------------------------
  // 5. HUD（ヘッドアップディスプレイ）ガイダンス＆免許色分岐テキスト描画
  // -------------------------------------------------------------
  // イベント停車中、またはじゃんけん結果画面の時、HUDウィンドウを展開
  if (isForcedStop || hmiChoice == 3 || currentGameState == STATE_RESULT) {
    fill(0, 0, 0, 180);               // 半透明（不透明度180）の黒い背景ボード
    rect(15, 110, 450, 220, 8); 
    stroke(255, 200, 0);
    makeStrokeWeightFix(2);
    noFill();
    rect(15, 110, 450, 220, 8);       // HUDの外枠（警告のイエローゴールド線）
    
    textAlign(LEFT, TOP);               // 文字の配置基準を左上に設定
    noStroke();
    
    fill(255, 230, 0);
    textSize(16);
    text("TRAFFIC INTERACTION (ROUND " + (matchCount + 1) + " / 3)", 30, 125); // 現在の遭遇ラウンド数を表示
    fill(255);
    textSize(14);

    // --- 各サブゲーム状態に応じたHUD内テキストの切り替え ---
    if (currentGameState == STATE_STANDBY) {
      text("【ステップ 1: カメラ調整】", 30, 160);
      fill(200, 255, 200);
      text("カメラに手を[グー]の形で提示して", 30, 190);
      text("[SPACE] キーを押してください．", 30, 210);
      fill(255);
    } 
    
    else if (currentGameState == STATE_READY) {
      // 【画像処理判定のコアロジック】
      // 1つの色のピクセル数が基準値（3500画素）を超えているかを評価し、カード色（免許証の種類）を特定
      if (countYellow > 3500) {
        userHand = "GOLD_LICENSE";      // 黄色優位ならゴールド免許
      } else if (countGreen > 3500) {
        userHand = "GREEN_LICENSE";     // 緑色優位ならグリーン免許
      } else if (countBlue > 3500) {
        userHand = "BLUE_LICENSE";      // 青色優位ならブルー免許
      } else {
        // カード類が検出されない場合、通常の「手の面積比（標本化比較）」によるじゃんけん認識アルゴリズムを実行
        float ratio = 0.0;
        if (guBasePixels > 0 && skinPixelsCount > 3500) {
          // 【講義解説要素】初期化時のグー（すぼめた手）の画素数に対する、現在の肌色画素数の「面積比（倍率）」を算出
          ratio = (float)skinPixelsCount / guBasePixels;
          if (ratio < 1.25)       userHand = "ROCK";     // 面積がほぼ同じなら「グー」
          else if (ratio < 1.65)  userHand = "SCISSORS"; // 指が2本出て少し面積が増えたら「チョキ」
          else                    userHand = "PAPER";    // 手の平が開いて面積が大幅に増えたら「パー」
        } else {
          userHand = "UNKNOWN";          // 何も映っていないか、肌色が少なすぎる場合
        }
      }

      text("【ステップ 2: 勝負！】", 30, 160);
      textSize(18);
      
      // ユーザーの現在リアルタイムに画像認識されている結果をHUD内にカラー付きでフィードバック
      if (userHand.equals("GOLD_LICENSE")) {
        fill(255, 215, 0);
        text("検出: ゴールド免許", 30, 190);
      } else if (userHand.equals("GREEN_LICENSE")) {
        fill(50, 255, 50);
        text("検出: グリーン免許", 30, 190);
      } else if (userHand.equals("BLUE_LICENSE")) {
        fill(100, 150, 255);
        text("検出: ブルー免許", 30, 190);
      } else {
        fill(0, 255, 255);
        // 【修正反映】内部識別用の英語文字列（ROCK/SCISSORS/PAPER）を、ユーザーへ分かりやすく日本語にローカライズ変換して表示
        String jpUserHand = "判定中...";
        if (userHand.equals("ROCK"))      jpUserHand = "グー";
        else if (userHand.equals("SCISSORS")) jpUserHand = "チョキ";
        else if (userHand.equals("PAPER"))    jpUserHand = "パー";
        
        text("あなたの手: " + jpUserHand, 30, 190);
      }
      
      textSize(14);
      fill(255);
      text("確定したら [ENTER] で対抗車と対面！", 30, 230);
    } 
    
    else if (currentGameState == STATE_RESULT) {
      // 確定キー入力後の勝敗・ゲーム性インタラクション結果ボード
      text("【判定結果】", 30, 160);
      textSize(16);
      
      // 特殊カード判定A：グリーン免許（初心者）を提示した場合、心理的に対向車が威圧（先攻・マウント）してくるシナリオ（自動的にユーザーの負け）
      if (userHand.equals("GREEN_LICENSE")) {
        fill(255, 100, 100);
        textSize(18);
        text("対抗車「君より熟練者だから先行くね」", 30, 200);
        textSize(20);
        text("結果: 負け... (対抗車が通過します)", 30, 240);
      } 
      // 特殊カード判定B：ブルー免許（一般）を提示した場合、対向車と同格となり「公平にじゃんけんしよう」と促されフリーズ状態（再戦要求）になる
      else if (userHand.equals("BLUE_LICENSE")) {
        fill(150, 180, 255);
        textSize(16);
        text("システム「同じ免許の色だし平等にじゃんけんしよう」", 30, 200);
        textSize(20);
        text("結果: あいこ（じゃんけん！)", 30, 240);
      } 
      // 特殊カード判定C：ゴールド免許（優良運転者）を提示した場合、圧倒的な社会的信用により対向車が恐縮して道を譲る（確定でプレイヤーの不戦勝）
      else if (userHand.equals("GOLD_LICENSE")) {
        fill(255, 255, 100);
        textSize(18);
        text("対抗車「ゴールド免許だと...！」", 30, 200);
        textSize(20);
        text("結果: 不戦勝！ (あなたが先に通過します)", 30, 240);
      } 
      // カードがない場合：ピュアな「じゃんけん（面積比）」対抗ロジックの判定結果の出力
      else {
        // 【修正反映】じゃんけん勝負画面の英字を、完全に親しみやすい日本語に変換して表示
        String jpUserHand = "不明";
        if (userHand.equals("ROCK"))      jpUserHand = "グー";
        else if (userHand.equals("SCISSORS")) jpUserHand = "チョキ";
        else if (userHand.equals("PAPER"))    jpUserHand = "パー";

        String jpSysHand = "不明";
        if (sysHand.equals("ROCK"))       jpSysHand = "グー";
        else if (sysHand.equals("SCISSORS"))  jpSysHand = "チョキ";
        else if (sysHand.equals("PAPER"))     jpSysHand = "パー";

        text("あなた: " + jpUserHand + "  vs  対抗車: " + jpSysHand, 30, 190);
        
        if (roundResult.equals("YOU WIN!")) {
          fill(255, 255, 0);
          textSize(20);
          text("結果: 勝ち！ (あなたが先に通過します)", 30, 220);
        } else if (roundResult.equals("YOU LOSE...")) {
          fill(255, 100, 100);
          textSize(20);
          text("結果: 負け... (対抗車に道を譲ります)", 30, 220);
        } else {
          fill(255);
          textSize(20);
          text("結果: あいこ！ (もう一度勝負！)", 30, 220);
        }
      }
      
      textSize(14);
      fill(255);
      text("確認したら [SPACE] を押してください。", 30, 290);
    }
  }

  // 通常走行中のみ、上下矢印キーによる自車スピードの無段階加減速を許可
  if (keyPressed && !isForcedStop && hmiChoice != 3 && currentGameState != STATE_GOAL) {
    if (keyCode == UP)         speed = min(speed + 0.1, 15);  // 最高速度を15にクリップ限制
    else if (keyCode == DOWN)  speed = max(speed - 0.1, 0);   // 最低速度0（バックはなし）
  }

  // -------------------------------------------------------------
  // 6. ゴールリザルト画面のオーバーレイ描画
  // -------------------------------------------------------------
  if (currentGameState == STATE_GOAL) {
    // 自車が家に完全に大接近したか、速度が完全にゼロになって停車した場合
    if (goalParam >= 1.0 || speed < 0.05) {
      speed = 0;                  // 物理速度を完全に固定
      goalParam = 1.0;  

      goalFade = min(goalFade + 4, 255); // フェードインカウンタを毎フレーム4ずつ加算（最大255不透明）

      fill(0, 0, 10, goalFade * 0.75); // リザルト背景のクリアダークブルー（フェード連動）
      rect(50, 100, width - 100, height - 250, 12);
      stroke(255, 255, 200, goalFade);
      makeStrokeWeightFix(2); 
      rect(50, 100, width - 100, height - 250, 12); // 金枠のフェード描画

      textAlign(CENTER, CENTER);      // テキスト配置を完全に中央寄せに設定
      noStroke();
      fill(255, 255, 0, goalFade);
      textSize(32);
      text("我が家に無事到着しました！", width / 2, height / 2 - 80);

      fill(255, 255, 255, goalFade);
      textSize(24);
      text("じゃんけん戦績: 3戦 中 " + userWins + " 勝", width / 2, height / 2 - 10); // 累積結果の開示

      // 勝利数（3回の交通対面インタラクションの総合戦績）によるドライバーの心理・脳内セリフの分岐表示
      textSize(20);
      if (userWins == 3) {
        fill(255, 255, 100, goalFade);
        text("「今日は運がいいな～」", width / 2, height / 2 + 50);
      } else if (userWins == 2) {
        fill(220, 220, 255, goalFade);
        text("「まー悪くないか」", width / 2, height / 2 + 50);
      } else if (userWins == 1) {
        fill(245, 180, 130, goalFade);
        text("「じゃんけん強いと思ったんだけどな～」", width / 2, height / 2 + 50);
      } else { 
        fill(180, 180, 200, goalFade);
        text("「今日は運悪いな...早く寝よう...」", width / 2, height / 2 + 50);
      }

      fill(160, goalFade);
      textSize(14);
      text("Press 'R' to restart simulator", width / 2, height / 2 + 120); // リスタートの案内文
    }
  }

  // --- 画面上部の中央ガイダンス（安全警告アナウンス）のテキスト更新 ---
  if (hmiChoice == 0 && isForcedStop) {
    fill(255, 50, 50);                // 警告の赤色
    textSize(20);
    textAlign(CENTER, TOP);
    text("STOP: VEHICLE AHEAD ON THE NARROW ROAD", width / 2, 25); // 前方にボトルネック車両ありの警告
  } else if (hmiChoice == 3) {
    fill(255, 150, 0);                // 注意のオレンジ
    textSize(20);
    textAlign(CENTER, TOP);
    text("EQUAL LICENSES: PRESS [SPACE] TO RE-TRY", width / 2, 25); // 免許同格（またはあいこ）につき再判定要求
  } else if (currentGameState == STATE_GOAL) {
    fill(100, 255, 100);              // 安全の緑色
    textSize(22);
    textAlign(CENTER, TOP);
    text("ARRIVING AT HOME...", width / 2, 25); // 目的地接近中のガイダンス
  }

  // -------------------------------------------------------------
  // 7. 【入力制御】キーボードのトリガー判定（エッジ検出）
  // -------------------------------------------------------------
  // keyPressed（押しっぱなしで真）と lastKeyPressed（前フレームの状態）の組み合わせにより、ボタンが「押された瞬間」だけ実行する
  if (keyPressed && !lastKeyPressed) {

    // 全ステート共通：'R'が押されたらすべての変数を初期化してゲームを最初からリスタート
    if (key == 'r' || key == 'R') {
      currentGameState = STATE_DRIVING;
      carState = 0;
      hmiChoice = 0;
      isForcedStop = false;
      speed = 5.0;
      goalParam = 0.0;
      goalFade = 0;
      guBasePixels = 0;
      matchCount = 0;
      userWins = 0;
      userHand = "UNKNOWN";
      sysHand = "UNKNOWN";
      roundResult = "";
    }

    // ステップ1（キャリブレーション待ち）でスペースが押された時、現在の肌色面積を「グーの基準」として記憶し勝負へ移行
    else if (currentGameState == STATE_STANDBY && key == ' ') {
      // 画面内に何かしらの手またはカード（3500画素以上）が存在する場合のみロックを許可（空振りの防止）
      if (skinPixelsCount > 3500 || countYellow > 3500 || countGreen > 3500 || countBlue > 3500) {
        guBasePixels = skinPixelsCount; // 現在の肌色画素数を面積基準値としてセーブ
        currentGameState = STATE_READY; // ステートをリアルタイム判定中（状態2）へ移行
      }
    } 
    
    // ステップ2（じゃんけん勝負中）にENTERキーで手を確定。対向車のNPCと勝敗の突き合わせを行う
    else if (currentGameState == STATE_READY && key == ENTER) {
      if (!userHand.equals("UNKNOWN")) { // 不明な状態での誤入力をガード
        
        // 分岐A: プレイヤーがグリーン免許を提示していたら無条件で負けイベントをセット
        if (userHand.equals("GREEN_LICENSE")) {
          roundResult = "YOU LOSE...";
          hmiChoice = 1;              // 対向車が先に行く挙動を命令
          matchCount++;               // 対戦回数を加算
        } 
        // 分岐B: プレイヤーがブルー免許を提示していたら「あいこ・保留」をセットしてパッシング状態へ
        else if (userHand.equals("BLUE_LICENSE")) {
          roundResult = "DRAW";
          hmiChoice = 3;              // HMIをフリーズ・点滅状態へ
        } 
        // 分岐C: プレイヤーがゴールド免許を提示していたら無条件で勝利イベントをセット
        else if (userHand.equals("GOLD_LICENSE")) {
          roundResult = "YOU WIN!";
          hmiChoice = 2;              // 自車が追い抜く挙動を命令
          isForcedStop = false;       // 自車の停車ロックを先行解除
          speed = 2.0;                // 追い抜き用の低速発進
          userWins++;                 // 累積勝利数をインクリメント
          matchCount++;               // 対戦回数を加算
        } 
        // 分岐D: 免許証ではなく、通常のじゃんけん（グー・チョキ・パーの面積比）でのガチンコ勝負
        else {
          int rand = (int)random(3);  // 0, 1, 2 の乱数を生成して対向車の手を決定
          if (rand == 0)      sysHand = "ROCK";
          else if (rand == 1) sysHand = "SCISSORS";
          else                sysHand = "PAPER";

          // じゃんけんの勝敗判定アルゴリズム（文字列比較による真理値評価）
          if (userHand.equals(sysHand)) {
            roundResult = "DRAW";
            hmiChoice = 3;            // あいこなのでフリーズ・点滅
          } else if ((userHand.equals("ROCK") && sysHand.equals("SCISSORS")) ||
            (userHand.equals("SCISSORS") && sysHand.equals("PAPER")) ||
            (userHand.equals("PAPER") && sysHand.equals("ROCK"))) {
            // プレイヤーの勝ちパターン
            roundResult = "YOU WIN!";
            hmiChoice = 2;            // 自車先行挙動
            isForcedStop = false;
            speed = 2.0;
            userWins++;
          } else {
            // プレイヤーの負けパターン
            roundResult = "YOU LOSE...";
            hmiChoice = 1;            // 対向車先行挙動
          }

          // じゃんけんの結果があいこ（DRAW）でなかった場合のみ、正式なエンカウント完了としてカウントを進める
          if (!roundResult.equals("DRAW")) {
            matchCount++;
          }
        }
        currentGameState = STATE_RESULT; // ステートを結末表示（状態3）へ移行
      }
    } 
    
    // ステップ3（結果表示画面）でスペースキーを押して確認。対向車を動かすか再戦するかを決定し元の道路へ戻る
    else if (currentGameState == STATE_RESULT && key == ' ') {
      if (hmiChoice == 3) { 
        currentGameState = STATE_STANDBY; // あいこ（またはブルー免許）ならステップ1（再認識）へループバック
      } else {
        currentGameState = STATE_DRIVING; // 勝敗がついていれば、対向車の通過アニメーションを裏で走らせつつ通常走行へ復帰
      }
    }
  }

  // 現在のフレームのキー押し下げ状態を記録し、次フレームでの長押し重複検知をブロックする
  lastKeyPressed = keyPressed;
}

// =============================================================
// カプセル化されたラッパー関数（線の太さ設定）
// =============================================================
void makeStrokeWeightFix(float w) {
  strokeWeight(w); // Processing標準の線幅指定関数を実行
}

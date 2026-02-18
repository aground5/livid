# LiveWallpaperEnabler

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

**LiveWallpaperEnabler**는 로컬 동영상이나 YouTube 영상을 **macOS 네이티브 라이브 월페이퍼(Aerial)**로 변환해주는 강력한 macOS 유틸리티입니다.

단순히 동영상을 배경 위에 띄우는 일반적인 월페이퍼 앱들과 달리, 이 도구는 **동영상 파일의 헤더를 패치**하고 macOS 시스템 월페이퍼 데이터베이스(`entries.json`)에 직접 주입합니다. 따라서 여러분이 만든 커스텀 월페이퍼는 Apple의 공식 Aerial 영상과 똑같이 작동합니다. 잠금 화면(Lock Screen)에서 재생되고, 슬로우 모션(고프레임)을 지원하며, macOS 고유의 "Liquid" 화면 전환 효과와도 완벽하게 통합됩니다.

---

## 📸 스크린샷 (Screenshots)

| **보관함 및 가져오기 (Library & Import)** | **편집 및 트리밍 (Trim & Editor)** |
|:---:|:---:|
| <!-- Insert Library Screenshot Here --> | <!-- Insert Editor Screenshot Here --> |
| *로컬 파일 탐색 및 YouTube 영상 다운로드* | *프레임 단위의 정밀한 구간 편집 및 미리보기* |

| **시스템 통합 (System Integration)** | **렌더링 대기열 (Render Queue)** |
|:---:|:---:|
| <!-- Insert System Settings Screenshot Here --> | <!-- Insert Render Queue Screenshot Here --> |
| *시스템 설정(System Settings)에 월페이퍼가 네이티브로 표시됨* | *FFmpeg를 이용한 백그라운드 트랜스코딩* |

---

## ✨ 핵심 기능 (Key Features)

*   **네이티브 Aerial 주입 (Native Aerial Injection)**: MOV 파일의 Atom 구조(`moov`, `trak`, `csgm`, `sgpd`, `tapt`)를 분석하고 패치하여, 커스텀 비디오를 macOS 공식 다이내믹 월페이퍼로 인식되게 만듭니다.
*   **'골든 포뮬러' 트랜스코딩 ("The Golden Formula" Transcoding)**: 커스텀 빌드된 정적 FFmpeg 엔진(`WebMSupport`)을 내장하여, macOS 잠금 화면 재생에 필수적인 **10-bit HEVC** 포맷과 GOP 구조로 완벽하게 변환합니다.
*   **스마트 화질 엔진 (Smart Quality Engine)**: HDR, 광색역(P3), High Chroma 콘텐츠를 자동으로 감지하고, 지능형 톤매핑(Tone-mapping) 또는 4:4:4 다운샘플링 전략을 적용합니다.
*   **통합 YouTube 다운로더**: 번들링된 `yt-dlp` 바이너리와 `YouTubeKit`을 통해 최대 **8K HDR** 영상을 메타데이터와 함께 자동으로 다운로드합니다.
*   **시스템 카탈로그 관리**: 시스템의 `entries.json` 매니페스트를 수정하여, 사용자 정의 카테고리를 생성하고 macOS 배경화면 설정에 에셋을 직접 등록합니다.
*   **XPC 헬퍼 아키텍처**: 권한이 필요한 작업(FFmpeg 트랜스코딩, 바이너리 실행 등)을 별도의 XPC 헬퍼 서비스로 분리하여 메인 UI 스레드의 차단을 방지하고 안정성을 높였습니다.

---

## 🛠 기술 스택 (Tech Stack)

*   **UI 프레임워크**: SwiftUI (macOS 14+), 시각 효과를 위한 AppKit 상호 운용.
*   **비디오 코어**: `AVFoundation`, `VideoToolbox`, 커스텀 C++ 브릿지를 통한 `FFmpeg` (libavcodec, libx265, libplacebo).
*   **파싱 (Parsing)**: MOV 헤더의 바이너리 조작을 위해 Swift로 직접 구현한 QuickTime Atom Parser (`QtParser`).
*   **네트워킹**: `Hummingbird` (로컬 에셋 서버) & `NSXPCConnection`.
*   **의존성**: `YouTubeKit`, `yt-dlp`, `deno` (JS 실행 환경).

---

## 🚀 시작하기 (Getting Started)

### 요구 사양 (Prerequisites)

*   macOS 14.0 (Sonoma) 이상.
*   빌드를 위한 Xcode 15.0 이상.
*   **Homebrew** (FFmpeg 빌드 툴 설치를 위해 필요).

### 설치 (Installation)

1.  **저장소 클론:**
    ```bash
    git clone https://github.com/yourusername/LiveWallpaperEnabler.git
    cd LiveWallpaperEnabler
    ```

2.  **정적 FFmpeg 라이브러리 빌드:**
    이 프로젝트는 특정 라이브러리(`libx265`, `libplacebo`, `libdav1d`)가 포함된 커스텀 정적 FFmpeg 빌드에 의존합니다. 포함된 빌드 스크립트를 실행하세요:
    ```bash
    chmod +x build_ffmpeg_static.sh
    ./build_ffmpeg_static.sh
    ```
    *이 과정은 몇 분 정도 소요될 수 있습니다.*

3.  **프로젝트 열기:**
    Xcode에서 `LiveWallpaperEnabler/LiveWallpaperEnabler.xcodeproj`를 엽니다.

4.  **빌드 및 실행:**
    `LiveWallpaperEnabler` 스킴을 선택하고 실행합니다 (Cmd+R).
    *참고: 빌드 단계에서 XPC 서비스(`LiveWallpaperHelper`)가 올바르게 임베드되었는지 확인하세요.*

### 사용 방법 (Usage)

1.  **가져오기 (Import)**: **Start** 탭에서 동영상 파일을 드래그 앤 드롭하거나 YouTube URL을 붙여넣습니다.
2.  **준비 (Prepare)**: 앱이 영상의 메타데이터(HDR, 프레임레이트, 비트레이트 등)를 분석합니다.
3.  **편집 (Edit)**: **Editor** 탭으로 이동하여 영상을 트리밍합니다. "Side-by-Side" 뷰를 사용해 시작과 끝 루프가 자연스러운지 비교할 수 있습니다.
4.  **렌더링 (Render)**: 렌더링 대기열에 추가합니다. 앱이 macOS 호환성을 위해 "골든 포뮬러"를 적용하여 영상을 트랜스코딩합니다.
5.  **등록 (Register)**: **Library** 탭으로 이동하여 렌더링된 월페이퍼를 우클릭하고 **"Add to System Catalog"**를 선택합니다.
6.  **적용 (Apply)**: macOS **시스템 설정 -> 배경화면**을 엽니다. 여러분이 만든 커스텀 카테고리와 월페이퍼가 나타날 것입니다.

---

## 📂 프로젝트 구조 (Project Structure)

```bash
.
├── LiveWallpaperEnabler
│   ├── App                 # 엔트리 포인트 및 시각 효과 뷰
│   ├── Core
│   │   ├── Export          # 트랜스코딩 로직
│   │   ├── Models          # 미디어 및 Aerial 매니페스트 모델
│   │   ├── Network         # YouTube 및 XPC 연결 로직
│   │   ├── QtParser        # 커스텀 QuickTime Atom 파서/라이터
│   │   ├── Services        # 렌더링 큐, Aerial 서비스, 썸네일 매니저
│   │   └── Storage         # 월페이퍼 영구 저장소
│   ├── Features            # SwiftUI 뷰 (Main, Editor, Library, Catalog)
│   └── LiveWallpaperHelper # XPC 서비스 (특권 작업, 바이너리 매니저)
├── WebMSupport             # Swift 패키지: FFmpeg 및 트랜스코딩용 C++ 브릿지
├── YouTubeKit              # Swift 패키지: YouTube 메타데이터 추출
└── build_ffmpeg_static.sh  # FFmpeg 의존성 빌드 스크립트
```

---

## ⚠️ 주의사항 (Disclaimer)

이 도구는 시스템 애플리케이션 지원 디렉토리의 구성 파일(`entries.json`)을 수정하여 월페이퍼를 주입합니다. 안전하게 설계되었지만, 만약을 위해 중요한 데이터는 백업하는 것을 권장합니다. 앱 내 헬퍼 서비스에는 "Health Check" 기능이 포함되어 있습니다.

이 프로젝트는 교육 목적으로 제작되었습니다. YouTube에서 다운로드한 영상의 저작권을 준수해 주시기 바랍니다.

---

## 📄 라이선스 (License)

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 `LICENSE` 파일을 참조하세요.

**의존성 라이선스 참고**:
*   **FFmpeg**: LGPL/GPL 라이선스를 따릅니다.
*   **yt-dlp**: Unlicense/Public Domain입니다.
*   **YouTubeKit**: MIT 라이선스를 따릅니다.

---

## 📧 연락처 (Contact)

**작성자**: [Your Name/Handle]
**이슈(Issues)**: 버그나 기능 요청은 GitHub Issues에 등록해 주세요.
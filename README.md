<p align="center"><img src="docs/images/logo.png" width="128" alt="Tidemark 로고"></p>

<h1 align="center">Tidemark</h1>

<p align="center">Claude 플랜의 사용량 한도를 macOS 메뉴 막대에서 봅니다.</p>

<p align="center"><b>한국어</b> · <a href="README.en.md">English</a></p>

<p align="center">
  <a href="https://github.com/lcalmsky/tidemark/releases/latest"><img src="https://img.shields.io/github/v/release/lcalmsky/tidemark?label=release&color=5b6cff" alt="최신 릴리즈"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-111111" alt="macOS 13 이상">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT 라이선스"></a>
</p>

<p align="center"><img src="docs/images/menubar.png" alt="Tidemark 가 메뉴 막대에 한도별 링과 퍼센트, 리셋까지 남은 시간을 그린 모습"></p>

<br>

## 빠른 시작

```sh
brew tap lcalmsky/tidemark https://github.com/lcalmsky/tidemark
brew trust lcalmsky/tidemark
brew install lcalmsky/tidemark/tidemark
brew services start lcalmsky/tidemark/tidemark
```

메뉴 막대 오른쪽에 한도별 링이 생깁니다. `⌘` 를 누른 채 링을 끌면 메뉴 막대에서 링의 자리를 옮길 수 있습니다.

<br>

## 기능

### 메뉴 막대

한도마다 왼쪽부터 링, 퍼센트, 리셋까지 남은 시간 순서로 그립니다.

| 보이는 것 | 뜻 |
|---|---|
| 링 안의 글자 | 한도 종류를 나타냅니다. `S` 는 세션 한도이고 청록색입니다. `W` 는 모든 모델을 합친 주간 한도이고 남색입니다. 모델별 주간 한도는 모델 이름의 첫 글자를 쓰고, Fable 은 보라색, 그 밖의 모델은 회색입니다 |
| 16px 링 | 그 한도의 사용률을 나타냅니다. 12시 방향에서 시계 방향으로 채우고, 남은 몫은 흐린 트랙으로 남깁니다. 채움은 50% 까지 링 안 글자와 같은 색을 쓰고, 75% 까지 주황색으로, 100% 까지 빨간색으로 조금씩 바뀝니다 |
| 퍼센트 | 사용률을 반올림한 값입니다. 75% 이상이면 주황색, 90% 이상이면 빨간색으로 그립니다 |
| 퍼센트 옆 시간 | 리셋까지 남은 시간입니다. `2d3h`, `4h12m`, `45m` 처럼 줄여 씁니다 |

앱을 켠 뒤 첫 응답이 오기 전에는 `C …` 를 그리고, 조회에 실패하면 뒤에 `?` 를 붙입니다. 한도는 5분마다 다시 조회하고, 남은 시간은 1분마다 다시 그립니다.

### 메뉴

메뉴 막대의 링을 누르면 다음 항목이 나옵니다.

- 맨 위에 `계정: <이메일> (<플랜>)` 이 나옵니다. 이메일을 읽지 못하면 설정 디렉터리 이름을 대신 보여 줍니다.
- 한도마다 `세션  42%  · 리셋까지 4h 12m` 같은 줄이 나옵니다. 모델별 주간 한도는 `주간` 대신 모델 이름을 씁니다.
- 마지막으로 성공한 시각을 `갱신: 14:05` 로 보여 줍니다.
- 조회에 실패했으면 `오류: ...` 줄이 함께 나옵니다.
- `지금 새로고침 ⌘R` 은 즉시 다시 조회합니다.
- `종료 ⌘Q` 는 앱을 끝냅니다.

<br>

## 계정 선택

앱은 Claude Code 가 쓰는 계정의 토큰만 읽고, 다른 계정의 토큰으로 넘어가지 않습니다.

- Orca 앱에서 Claude 계정을 고르면 `~/Library/Application Support/orca/claude-profiles/selected-host` 파일에 그 계정의 설정 디렉터리가 기록됩니다. 앱은 이 파일이 있으면 그 디렉터리를 씁니다. 키체인 서비스 이름은 `Claude Code-credentials-<디렉터리 경로 SHA-256 앞 8자리>` 이고, 이메일은 `<디렉터리>/.claude.json` 에서 읽습니다.
- 이 파일이 없거나 비어 있으면 기본 계정을 씁니다. Orca 는 기본 계정을 고르면 이 파일을 빈 내용으로 남깁니다. 키체인 서비스 이름은 `Claude Code-credentials` 이고, 이메일은 `~/.claude.json` 에서 읽습니다.
- 파일이 있는데 읽지 못하면 기본 계정으로 넘어가지 않고 `계정 선택 파일 읽기 실패` 를 표시합니다.
- 선택한 계정의 키체인 항목이 없으면 오류로 표시하고 다른 계정의 토큰을 찾지 않습니다.
- 앱은 60초마다 계정이 바뀌었는지 확인하고, 바뀌었으면 이전 계정의 수치를 지운 뒤 새로 조회합니다.

<br>

## 요구 사항

| 조건 | 비고 |
|---|---|
| macOS 13 이상 | AppKit 메뉴 막대 앱입니다 |
| Xcode Command Line Tools | `swift build` 로 빌드합니다. 없으면 `xcode-select --install` 로 설치하거나 `brew install swift` 로 Swift 툴체인을 설치합니다 |
| Claude Code 로그인 | Claude 구독이 있는 계정으로 로그인해 두어야 한도를 읽습니다 |

<br>

## 제거

```sh
brew services stop lcalmsky/tidemark/tidemark
brew uninstall lcalmsky/tidemark/tidemark
brew untap lcalmsky/tidemark
```

세 줄을 차례로 실행하면 서비스가 멈추고 앱과 tap 이 제거됩니다.

<br>

## 개발

```sh
swift build
scripts/bundle.sh           # build/Tidemark.app 을 만든다
```

- **앱 아이콘** `swift scripts/make-icon.swift` 가 `assets/AppIcon.icns` 를 다시 만들고, `scripts/bundle.sh` 가 그 파일을 번들에 넣습니다.
- **릴리즈** `scripts/release.sh X.Y.Z -m "<바뀐 기능 요약>"` 하나로 버전, 빌드, 검사, 태그, GitHub Release, Homebrew formula 갱신을 합니다. tarball 을 받는 단계에서 멈췄다면 `scripts/release.sh --formula-only X.Y.Z` 로 formula 갱신만 다시 합니다.

<br>

## 알아 둘 점

- 앱은 `https://api.anthropic.com/api/oauth/usage` 를 씁니다. 공개 문서에 없는 주소라서 예고 없이 바뀔 수 있습니다. 응답 형식이 바뀌면 앱이 `?` 나 `오류` 로 표시합니다.
- 토큰은 `api.anthropic.com` 으로 보내는 요청의 인증 헤더에만 쓰고, 화면이나 로그 어디에도 출력하지 않습니다.

<br>

<p align="center"><a href="LICENSE">MIT</a></p>

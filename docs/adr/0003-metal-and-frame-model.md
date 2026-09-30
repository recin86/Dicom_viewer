# Metal 표시와 프레임 모델

상태: 제안. 날짜: 2026-09-30. 결정 시점: P0/P1. 관련 문서: [DICOM 지원 명세](../03-dicom-support.md), [시스템 아키텍처](../02-system-architecture.md), [화면과 조작](../05-ui-and-interaction.md).

## 배경

CT/MR 스택, X-ray 정지 영상과 US cine는 서로 다른 탐색 방식이 필요하지만 영상 표시와 확대·이동은 공유할 수 있다. window/level을 조작할 때마다 CPU에서 전체 이미지를 다시 만드는 경로는 피하고, 표시와 수치 계산의 의미를 분리할 필요가 있다.

## 선택 제안

SwiftUI로 일반 화면을 만들고 AppKit 기반 viewport와 MTKView를 연결한다. Rust가 프레임의 의미와 표시 설명을 제공하고 Metal은 텍스처에 VOI와 화면 변환을 적용한다.

도메인 모델은 Series 아래에 display set과 frame reference를 둔다. 탐색은 정지 영상, 공간 스택, 시간 시퀀스와 순서 목록으로 구분한다. 하나의 DICOM 파일을 하나의 이미지 또는 모든 시리즈를 3D 볼륨으로 고정하지 않는다.

회색조 초기 표시 버퍼는 Modality 변환 후 F32, 컬러는 RGBA8로 제안한다. 측정용 원본 값과 정밀한 변환 경로는 Rust에서 관리한다. CPU 기준 렌더러를 작은 시험 경로로 두어 GPU 출력과 비교한다.

표시용 픽셀 종횡비와 물리 측정 보정은 별개로 전달한다. shader의 보간·padding 처리와 좌표 변환 순서는 API 계약에 맞추고 CPU 기준 렌더러와 PNG 출력에서도 공유한다. 프레임·목록의 revision이 바뀌어도 기존 인덱스 번호만으로 표시 대상을 바꾸지 않는다.

MTKView는 Metal 표시용 뷰이며 NSViewRepresentable은 AppKit 뷰를 SwiftUI에 넣는 경계를 제공한다. [Apple MTKView](https://developer.apple.com/documentation/metalkit/mtkview/), [Apple NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)

## 검토한 대안

CPU에서 완성 이미지를 만들어 일반 이미지 뷰에 넣는 방식은 시작이 단순하지만 반복 window/level과 대형 영상에서 복사와 재계산 비용이 발생한다. 짧은 디코딩 실험에는 사용할 수 있으나 제품의 기본 표시 경로로는 GPU 방식을 우선 검증한다.

Rust에서 GPU 표시까지 맡기는 방식은 다른 플랫폼에 렌더링을 재사용할 수 있다. 현재 macOS 앱의 입력·리소스 수명과 결합하는 비용을 고려해 Swift/Metal 경계를 먼저 선택한다. 향후 다른 OS가 실제 요구가 되면 재평가한다.

## 결과

CPU와 GPU가 같은 VOI, 반전과 좌표 의미를 사용해야 한다. 회색조 F32 버퍼는 16비트 정수보다 메모리를 더 사용한다. 렌더러에는 환자 공간의 의미를 재해석하는 코드를 넣지 않고 DisplayDescriptor를 전달한다.

시간, 공간, echo 등의 의미가 불명확할 때 표시 순서만 제공할 수 있다. 이때 MPR이나 위치 연동을 활성화하지 않는 상태를 모델에서 표현해야 한다.

## 검증과 재검토

P1에서 회색조·컬러, LUT, MONOCHROME1과 최종 극성, Retina 좌표와 GPU 수명을 시험한다. P2에서 스택 및 cine의 성능과 자원 사용을 측정한다. F32 비용이 유의미하면 정수 텍스처 경로를 검토하되 Modality 변환의 적용 책임을 다시 명시한다.

# P0-FFI-CONTRACT 픽셀 전달 계약 실험

P0 전용 실험이다. 제품 API·`decode_frame`·GPU 표시·정식 T-11~T-13 합격을 뜻하지 않는다. Task `P0-FFI-CONTRACT`(상위 `P0-CLOSE-20260930`), 기준 commit `ea7e2b3`. 최초 착수 Codex/root(Cargo.toml·C 헤더 초안), 이후 Claude(Cowork)가 인수해 Rust·Swift·실행 스크립트를 작성했다. 기존 `experiments/p0-ffi/`는 동결하고 결과만 근거로 사용한다.

## 실행

대상 Mac에서 실행한다(Command Line Tools만 필요, Xcode 불필요).

```sh
bash experiments/p0-ffi-contract/run.sh
```

rustup의 Rust 1.98.1, UniFFI 0.32.2(`Cargo.lock` 고정), SwiftPM release, 정적 링크로 빌드한다. 순서: `cargo fmt --check` → `cargo test` → `cargo clippy -D warnings` → UniFFI Swift 바인딩 생성 → `swift build` → `P0ContractCheck`. 커밋 대상 결과는 `results/contract-results.json`과 `results/environment.json`(로컬 절대경로 없음)이고, 빌드 로그·바이너리는 `~/Library/Caches/dicom-viewer/p0-ffi-contract/`에 둔다. 생성 바인딩·복사한 헤더·정적 라이브러리는 `.gitignore` 대상이며 손으로 고치지 않는다.

## 기존 copy_into 감사 (P0-FFI-AUDIT)

Codex가 배정한 읽기 전용 감사 서브에이전트의 반환 결과는 저장소에 남지 않아, 인수 후 같은 범위를 다시 검토했다. 대상: `experiments/p0-ffi/rust/src/lib.rs`의 `FrameBuffer::copy_into`, `swift/Sources/P0Bench/main.swift`의 호출부, docs/02·docs/04 픽셀 전달·메모리 소유권 절, ADR 0002.

| ID | 관찰 | 영향 | 조치 |
| --- | --- | --- | --- |
| A1 | Swift 공개 메서드 `copyInto(dstAddr: UInt64, dstLen: UInt64)`가 임의 정수 주소를 받는다. Swift 쪽에 `unsafe` 표시가 없어 호출자 실수가 곧바로 메모리 손상이 된다 | 제품 계약으로 부적합 | 주소를 받지 않는 opaque ticket + 타입 있는 C 포인터 함수, 포인터는 Swift 래퍼 내부에만 둠 |
| A2 | 길이 검사가 `dst_len < len`만 거부한다. 더 큰 버퍼는 수락해 나머지 바이트가 정의되지 않는다 | docs/04의 `row_stride_bytes × height` 정확 길이와 불일치 | 정확 길이만 허용, 오류 시 대상 버퍼 미기록 |
| A3 | `FrameBuffer`에 pixel_format·row_stride·value_domain·valid_mask가 없다 | 소비자가 형식·stride를 검증할 수 없고 회색조 mask 경로가 없음 | 메타데이터는 UniFFI 객체, mask는 같은 ticket의 별도 복사 함수 |
| A4 | 대상 버퍼의 배타적 접근은 벤치마크 코드의 관례에만 의존한다 | 동시 쓰기·겹침 가능 | Swift 래퍼가 `inout`/자체 할당으로 배타성을 보장, Metal 대상은 GPU 미사용 구간이라는 호출자 의무를 명시 |
| A5 | 복사 중 원본 수명은 UniFFI 객체 handle이 보장하지만, 캐시 eviction·세션 close와의 관계를 copy 경로로는 시험하지 않았다(record 경로만 확인) | docs/04의 "반환 payload는 eviction·close와 독립" 계약 미검증 | 세션 캐시·evict·close·마지막 owner 해제 시험 추가 |
| A6 | panic 격리는 UniFFI의 Result 경로에 의존한다 | 직접 C 함수는 별도 `catch_unwind` 필요 | 모든 C 진입점을 `catch_unwind`로 감싸고 상태 코드로 반환 |
| A7 | 기존 실측(대상 Mac): into 경로 16 MiB 반복 footprint 평탄, 64 MiB 전달 p50 1.86 ms; record 경로는 호출당 약 1프레임 누적 | 권고 방향 자체는 유지 | 새 경로에서 같은 성질을 재측정 |
| A8 | docs/04·ADR 0002는 "소유된 bytes 반환"만 기술한다 | 권고 경로(Rust 보유 → Swift 소유 버퍼로 1회 복사)와 문서 불일치 | 실험 결과 확인 후 ADR 0002·docs/04 개정 |

## 계약 후보 (이 실험이 검증하는 내용)

- Rust는 디코딩된 불변 프레임(`FrameData`)을 `Arc`로 보유한다. UniFFI 객체 `PreparedFrame`이 width·height·pixel_format·value_domain·payload_revision·row_stride_bytes·byte_len·mask_len·checksum·copy_ticket을 제공한다. 세션 캐시(`ContractSession`)도 같은 프레임을 공동 소유한다.
- 픽셀과 mask 복사는 [p0_contract_copy.h](include/p0_contract_copy.h)의 C 함수 두 개다. ticket은 재사용하지 않는 불투명 ID이며, 레지스트리의 weak 참조를 복사 동안만 strong으로 올린다. 검사 순서는 ticket → null → mask 존재 → 정확 길이이고, 오류 1/2/3/5는 대상에 쓰지 않는다. 모든 진입점은 `catch_unwind`로 panic을 상태 4로 격리한다.
- Swift는 C 함수를 직접 부르지 않고 [FrameCopy.swift](swift/Sources/P0ContractCheck/FrameCopy.swift)의 래퍼만 쓴다. 래퍼는 `withExtendedLifetime(self)`로 ticket 유효 기간을 호출 동안 보장하고, 정확한 크기의 `[UInt8]`을 직접 할당하거나 `inout` 버퍼·shared `MTLBuffer`를 길이 검사 후 채운다.
- 수명: 이미 받은 `PreparedFrame`은 캐시 eviction·세션 close 뒤에도 유효하다. close 후 새 작업은 `SessionClosed`. 마지막 owner(Swift handle과 캐시)가 사라지면 ticket은 만료되어 `INVALID_TICKET`이 된다.
- 픽셀 의미는 docs/04를 따른다. GrayF32LE는 ModalityApplied, 무효 위치는 유한한 +0.0과 mask 0. RGBA8은 R,G,B,A 순서의 DisplayColor이고 mask가 없다.

## 시험 항목

| ID | 내용 | 독립 기대값 |
| --- | --- | --- |
| C01 | GrayF32LE 512×512 전 값 bit 일치, stride·길이·domain·revision | Swift에서 `x − 0.5y − 1024` 재계산 |
| C02 | 511×257 홀수 크기 + valid_mask, 무효 위치 +0.0·mask 0/1 | Swift에서 `(3x + y) % 11 == 0` 재계산 |
| C03 | RGBA8 300×200 채널 순서, mask 요청 → NO_MASK·미기록 | Swift 수식 |
| C04 | 짧음·긺·0 길이, null, 모르는 ticket, mask 길이 오류 → 상태 코드와 sentinel 미변경; 잘못된 prepare 거부 | 헤더 상태 코드 |
| C05 | eviction·close 후 보유 payload 유효, SessionClosed, 마지막 owner 해제 후 만료, 캐시 단독 owner | docs/04 수명 절 |
| C06 | 한 ticket의 8개 동시 복사 | 전 픽셀·checksum |
| C07 | 다른 스레드의 마지막 해제와 복사 경합 200회: 완전한 복사 또는 INVALID_TICKET, 부분·부활 없음 | checksum |
| C08 | C 경계 panic → 상태 4, 프로세스 계속 | — |
| C09 | 16 MiB 픽셀+4 MiB mask 40회 복사 중 Rust 할당 0 | 계수 할당기 |
| C10 | 64 MiB 프레임 재사용·새 버퍼 각 20회 footprint 평탄, 해제 후 Rust bytes 반환 | phys_footprint |
| C11 | 1/16/64 MiB 복사 시간(정보용) | — |
| C12 | shared `MTLBuffer` 대상 복사 일치, 크기 불일치 거부 (CPU 복사만, GPU pass 없음) | Swift 수식 |

## 결과 (대상 Mac, 2026-09-30)

환경: Apple M5(Mac17,3), 16 GiB, macOS 27.0(26A428), Rust/cargo 1.98.1, Swift 6.4 Command Line Tools(Xcode 없음), UniFFI 0.32.2, release, 정적 링크(`otool -L`에 libp0contract 없음), deployment target 14.0(실험 값이며 제품 기준 27.0 아님). 버전·소스·바이너리 SHA-256은 [environment.json](results/environment.json), 항목별 결과는 [contract-results.json](results/contract-results.json).

- Rust: `cargo fmt --check`, 단위 시험 5개(정확 복사·mask, 오류 미기록, ticket 수명, 동시 복사·해제 경합, panic 격리), `clippy -D warnings`, release build pass. 첫 Mac 실행에서 Rust 1.98 clippy의 `chunks_exact_to_as_chunks`와 Swift 배타 접근 검사(C09의 `mask.count`)에 걸려 각각 수정 후 재실행했다. 동작 의미는 바뀌지 않았다.
- 실행 이력: 1차 결과(12:49 UTC)는 C08의 detail 키 `status`가 검사 상태를 덮어써 summary pass 10으로 기록됐다(검사 자체는 반환 4로 통과, fail 0). P0 독립 검토(F1·F2·F6·F7)에 따라 detail을 `detail` 아래로 분리하고, C07 매 복사 전 sentinel 재충전, C04 실제 u64 곱셈 overflow 추가, C05 evict 실제 수행 확인, run.sh 시작 시 이전 결과 삭제를 반영해 **최종 재실행(13:04 UTC)** 했다. 아래 표는 최종 결과이며 environment.json의 소스 해시는 현재 파일과 일치한다.
- Swift 계약 검사: **C01~C10, C12 pass(11), C11 정보, fail 0, not-run 0.**

| ID | 결과 | 관찰 |
| --- | --- | --- |
| C01 | pass | 512×512 GrayF32LE 전 값 bit 일치, stride 2048·1 MiB·ModalityApplied·revision 1 |
| C02 | pass | 511×257 mask 무효 11,939개가 Swift 독립 계산과 일치, 무효 위치 +0.0 |
| C03 | pass | RGBA8 전 픽셀 일치, mask 요청 → 5(NO_MASK)·미기록 |
| C04 | pass | 짧음·긺·0·mask 길이 → 3, null → 2, ticket 0·미등록 → 1, sentinel 미변경; 0 크기 → InvalidArgument, 512 MiB 한도 초과·u64 크기 overflow → ResourceLimit, RGBA mask → InvalidArgument |
| C05 | pass | evict 실제 수행(캐시 0) 확인, eviction·close 뒤 보유 payload 복사 정상, close 후 prepare → SessionClosed, 마지막 owner 해제 → 1, 캐시 단독 owner 유효 후 evict → 1 |
| C06 | pass | 8개 동시 복사 전 픽셀·mask 일치 |
| C07 | pass | 200회 해제 경합(매 복사 전 sentinel 재충전): 정상 복사 4,411 / 만료 3,589 / 부분 0 / 부활 0 / 기타 0 |
| C08 | pass | C 경계 panic → 상태 4, 프로세스 계속 |
| C09 | pass | 16 MiB 픽셀 + 4 MiB mask 40회 복사 중 Rust 할당 0, live 변화 0 |
| C10 | pass | 64 MiB + mask 16 MiB: 재사용 버퍼 20회 208.13→208.13 MiB, 새 버퍼 20회 272.19→272.19 MiB, Rust live 변화 0 (해제 뒤 프로세스 footprint는 272 MiB로 남음: 할당기 보유로 보이며 누적은 아님, 원인 미확정) |
| C11 | 정보 | 재사용 p50/p95: 1 MiB 0.013/0.013 ms, 16 MiB 0.281/0.287 ms, 64 MiB 1.088/1.126 ms; 새 버퍼 64 MiB p50 1.088 ms (1차 실행도 같은 범위) |
| C12 | pass | Apple M5 shared `MTLBuffer` 목적지 전 값 일치, 4바이트 작은 버퍼 → 3 (CPU 복사만, GPU pass 없음) |

판단: 감사 항목 A1~A6을 해소한 계약 후보가 대상 Mac에서 양쪽 바인딩을 통과했다. 이 결과와 P0 독립 검토로 ADR 0002를 채택했다. C06·C07은 C01·C02에서 전 픽셀을 독립 검증한 뒤 producer checksum과 비교한다. 이 실험 모듈 안에서는 시험을 위해 C 함수를 직접 호출하므로, 제품에서는 C 모듈을 래퍼 모듈의 비공개 의존성으로 격리해야 한다(P1, 검토 F5). 한계: 합성 프레임만 사용했고 dicom-rs decode·요청 generation·취소·GPU 사용 완료와의 순서·실제 앱 메모리 예산은 시험하지 않았다(P1 이후). C 경계는 임의 비null 포인터의 할당·수명을 검증할 수 없으므로 안전성은 Swift 래퍼 전용 사용이라는 규칙에 의존한다.

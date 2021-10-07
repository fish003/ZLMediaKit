/*
 * Copyright (c) 2021 The ZLMediaKit project authors. All Rights Reserved.
 *
 * This file is part of ZLMediaKit(https://github.com/xia-chu/ZLMediaKit).
 *
 * Use of this source code is governed by MIT license that can be found in the
 * LICENSE file in the root of the source tree. All contributing project authors
 * may be found in the AUTHORS file in the root of the source tree.
 */

#include "TwccContext.h"
#include "Rtcp/RtcpFCI.h"

using namespace mediakit;

enum class ExtSeqStatus : int {
    normal = 0,
    looped,
    jumped,
};

void TwccContext::onRtp(uint16_t twcc_ext_seq) {
    switch ((ExtSeqStatus) checkSeqStatus(twcc_ext_seq)) {
        case ExtSeqStatus::jumped: /*回环后，收到回环前的大ext seq包,过滤掉*/ return;
        case ExtSeqStatus::looped: /*回环，触发发送twcc rtcp*/ onSendTwcc(); break;
        case ExtSeqStatus::normal: break;
        default: /*不可达*/assert(0); break;
    }

    auto result = _rtp_recv_status.emplace(twcc_ext_seq, _ticker.createdTime());
    if (!result.second) {
        WarnL << "recv same twcc ext seq:" << twcc_ext_seq;
        return;
    }

    _max_stamp = result.first->second;
    if (!_min_stamp) {
        _min_stamp = _max_stamp;
    }

    if (checkIfNeedSendTwcc()) {
        //其他匹配条件立即发送twcc
        onSendTwcc();
    }
}

bool TwccContext::checkIfNeedSendTwcc() const {
    auto size = _rtp_recv_status.size();
    if (!size) {
        return false;
    }
    if (size >= kMaxSeqDelta) {
        return true;
    }
    auto delta_ms = _max_stamp - _min_stamp;
    if (delta_ms >= kMaxTimeDelta) {
        return true;
    }
    return false;
}

int TwccContext::checkSeqStatus(uint16_t twcc_ext_seq) const {
    if (_rtp_recv_status.empty()) {
        return (int) ExtSeqStatus::normal;
    }
    auto max = _rtp_recv_status.rbegin()->first;
    if (max > 0xFF00 && twcc_ext_seq < 0xFF) {
        //发生回环了
        TraceL << "rtp twcc ext seq looped:" << max << " -> " << twcc_ext_seq;
        return (int) ExtSeqStatus::looped;
    }
    if (twcc_ext_seq - max > 0xFFFF / 2) {
        TraceL << "rtp twcc ext seq jumped:" << max << " -> " << twcc_ext_seq;
        return (int) ExtSeqStatus::jumped;
    }
    return (int) ExtSeqStatus::normal;
}

void TwccContext::onSendTwcc() {
    auto max = _rtp_recv_status.rbegin()->first;
    auto begin = _rtp_recv_status.begin();
    auto min = begin->first;
    auto ref_time = begin->second;
    FCI_TWCC::TwccPacketStatus status;
    for (auto seq = min; seq <= max; ++seq) {
        int16_t delta = 0;
        SymbolStatus symbol = SymbolStatus::not_received;
        auto it = _rtp_recv_status.find(seq);
        if (it != _rtp_recv_status.end()) {
            //recv delta,单位为250us,1ms等于4x250us
            delta = (int16_t) (4 * ((int64_t) it->second - (int64_t) ref_time));
            if (delta < 0 || delta > 0xFF) {
                symbol = SymbolStatus::large_delta;
            } else {
                symbol = SymbolStatus::small_delta;
            }
            ref_time = it->second;
        }
        status.emplace(seq, std::make_pair(symbol, delta));
    }
    auto fci = FCI_TWCC::create(ref_time / 64, _twcc_pkt_count, status);
    InfoL << ((FCI_TWCC *) (fci.data()))->dumpString(fci.size());

    ++_twcc_pkt_count;
    clearStatus();
}

void TwccContext::clearStatus() {
    _rtp_recv_status.clear();
    _min_stamp = 0;
}

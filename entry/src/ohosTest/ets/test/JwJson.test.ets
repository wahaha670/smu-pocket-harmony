/**
 * 教务 JSON 解析的单测。
 *
 * 这些用例覆盖原项目踩过的真实坑：
 * - 成绩接口的 `rows` 与 `data` 平级
 * - 未登录时 `data` 是空字符串（不是数组）
 * - 网点号字段是 `xid` 而不是 `xhk`
 * - 字段类型在数字和字符串之间漂移
 *
 * 用真实响应脱敏后的精简样例，不依赖网络。
 */
import { describe, it, expect } from '@ohos/hypium';
import { JwJson, flexInt, flexString, onlineExamNumber, scoreOf } from '../../../../main/ets/data/JwJson';

export default function jwJsonTest() {
  describe('JwJson', () => {
    it('parsesTimetableObjectForm', 0, () => {
      const body = JSON.stringify({
        code: 0,
        message: '成功',
        data: [
          { kcmc: '药理学', xq: 1, zc: '8', jcdm: '0304', jxcdmc: '教学馆 301' }
        ]
      });
      const r = JwJson.timetable(body);
      expect(r.code).assertEqual(0);
      expect(r.data.length).assertEqual(1);
      expect(r.data[0].kcmc).assertEqual('药理学');
      expect(r.data[0].xq).assertEqual(1);
      expect(r.data[0].zc).assertEqual('8');
    });

    it('parsesTimetableBareArray', 0, () => {
      const body = JSON.stringify([{ kcmc: '生理学', xq: 2, ps: '01', pe: '02' }]);
      const r = JwJson.timetable(body);
      expect(r.data.length).assertEqual(1);
      expect(r.data[0].kcmc).assertEqual('生理学');
    });

    // 关键回归：未登录时 data 是空字符串，不能抛异常
    it('handlesUnauthorizedEmptyStringData', 0, () => {
      const body = JSON.stringify({ code: -401, data: '', message: '尚未登录，请先登录' });
      const r = JwJson.timetable(body);
      expect(r.code).assertEqual(-401);
      expect(r.data.length).assertEqual(0);
      expect(r.message).assertEqual('尚未登录，请先登录');
    });

    it('parsesScoresFlatRows', 0, () => {
      const body = JSON.stringify({
        data: '',
        rows: [
          { kcmc: '系统解剖学', xnxqmc: '2025-2026-2', zcjfs: 91.0, cjjd: 4.1, xf: 4.0 }
        ],
        total: 50
      });
      const r = JwJson.scores(body);
      expect(r.rows.length).assertEqual(1);
      expect(r.total).assertEqual(50);
      expect(r.rows[0].kcmc).assertEqual('系统解剖学');
      expect(scoreOf(r.rows[0])).assertEqual(91.0);
    });

    it('parsesScoresNestedRows', 0, () => {
      const body = JSON.stringify({
        data: { rows: [{ kcmc: '生理学', xnxqmc: '2025-2026-2', zcjfs: '85.5' }], total: 1 }
      });
      const r = JwJson.scores(body);
      expect(r.rows.length).assertEqual(1);
      expect(scoreOf(r.rows[0])).assertEqual(85.5);
    });

    // 网点号：真实字段是 xid
    it('readsOnlineExamNumberFromXid', 0, () => {
      const body = JSON.stringify({
        data: '',
        rows: [{ kcmc: '药理学', xid: '7667619' }],
        total: 1
      });
      const r = JwJson.examTasks(body);
      expect(r.rows.length).assertEqual(1);
      expect(onlineExamNumber(r.rows[0])).assertEqual('7667619');
    });

    it('prefersXkhOverXid', 0, () => {
      const body = JSON.stringify({
        rows: [{ kcmc: '药理学', xkh: '111', xid: '222' }],
        total: 1
      });
      const r = JwJson.examTasks(body);
      expect(onlineExamNumber(r.rows[0])).assertEqual('111');
    });

    it('handlesMalformedJsonWithoutThrowing', 0, () => {
      const r = JwJson.timetable('<html>not json</html>');
      expect(r.data.length).assertEqual(0);
    });
  });

  describe('FlexibleTypes', () => {
    it('flexIntAcceptsNumberAndString', 0, () => {
      expect(flexInt(8)).assertEqual(8);
      expect(flexInt('8')).assertEqual(8);
      expect(flexInt('8.7')).assertEqual(8);
      expect(flexInt(null)).assertEqual(0);
      expect(flexInt('abc')).assertEqual(0);
    });

    it('flexStringAcceptsNumberAndString', 0, () => {
      expect(flexString('8')).assertEqual('8');
      expect(flexString(8)).assertEqual('8');
      expect(flexString(88.2)).assertEqual('88.2');
      expect(flexString(null)).assertEqual('');
    });
  });
}

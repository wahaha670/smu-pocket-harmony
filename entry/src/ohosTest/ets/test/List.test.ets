/**
 * 测试入口：聚合所有单测。
 *
 * 鸿蒙的测试框架要求有一个 index 导出所有测试套件。
 */
import semesterTest from './Semester.test';
import jwJsonTest from './JwJson.test';
import courseMergeTest from './CourseMerge.test';
import widgetDateTest from './WidgetDate.test';
import widgetDateBoundaryTest from './WidgetDateBoundary.test';

export default function testsuite() {
  semesterTest();
  jwJsonTest();
  courseMergeTest();
  widgetDateTest();
  widgetDateBoundaryTest();
}

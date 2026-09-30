const { SESClient, SendEmailCommand } = require('@aws-sdk/client-ses');
const ses = new SESClient({ region: 'ap-northeast-2' });

exports.handler = async (event) => {
    // SNS에서 온 메시지 파싱
    const message = JSON.parse(event.Records[0].Sns.Message);

    // 이메일 상세 설정
    const command = new SendEmailCommand({
        Source: 'no-reply@bidhouse.cloud', // SES 인증 도메인 기반 이메일
        Destination: { ToAddresses: ['dkdlemf07@gmail.com'] }, // 알림 받을 이메일
        Message: {
            Subject: { Data: `🚨 [BIDHOUSE] 시스템 관제 알림: ${message.AlarmName}` },
            Body: {
                Html: {
                    Data: `
                        <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #ddd; max-width: 600px;">
                            <h2 style="color: #e84040;">시스템 장애 발생!</h2>
                            <p><strong>알람명:</strong> ${message.AlarmName}</p>
                            <p><strong>상태:</strong> ${message.NewStateValue}</p>
                            <p><strong>발생 이유:</strong> ${message.NewStateReason}</p>
                            <div style="margin-top: 20px; padding: 10px; background-color: #f9f9f9; border-left: 5px solid #ccc;">
                                <p>신속한 확인을 위해 AWS 콘솔에 접속하세요.</p>
                            </div>
                        </div>
                    `
                }
            }
        }
    });

    try {
        await ses.send(command);
        return { statusCode: 200, body: '이메일 발송 성공!' };
    } catch (err) {
        console.error(err);
        return { statusCode: 500, body: '이메일 발송 실패' };
    }
};
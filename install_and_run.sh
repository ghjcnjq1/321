#!/bin/bash

# Проверим, установлен ли Python 3
if ! command -v python3 &> /dev/null
then
    echo "Python 3 не установлен. Устанавливаю..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv
else
    echo "Python 3 уже установлен"
fi

# Проверим, установлен ли pip
if ! command -v pip3 &> /dev/null
then
    echo "pip не установлен. Устанавливаю..."
    sudo apt-get install -y python3-pip
else
    echo "pip уже установлен"
fi

# Создание виртуального окружения
echo "Создаю виртуальное окружение..."
python3 -m venv venv

# Активируем виртуальное окружение
echo "Активирую виртуальное окружение..."
source venv/bin/activate

# Устанавливаем необходимые библиотеки
echo "Устанавливаю Flask, psutil и Gunicorn..."
pip install flask psutil gunicorn

# Создание файла app.py с кодом
echo "Создаю файл app.py..."
cat > app.py << 'EOF'
from flask import Flask, jsonify
import psutil
import time

app = Flask(__name__)

def get_system_metrics():
    disks = {}
    for part in psutil.disk_partitions():
        try:
            usage = psutil.disk_usage(part.mountpoint).percent
            disks[f"Disk {part.device}"] = usage
        except PermissionError:
            continue  # Игнорируем недоступные диски

    net_io = psutil.net_io_counters()
    uptime = time.time() - psutil.boot_time()  # Время работы системы в секундах

    # Переводим секунды в часы, минуты и секунды
    hours = int(uptime // 3600)
    minutes = int((uptime % 3600) // 60)
    seconds = int(uptime % 60)

    return {
        "CPU": psutil.cpu_percent(interval=1),
        "Memory": psutil.virtual_memory().percent,
        "Swap": psutil.swap_memory().percent,
        "Network Sent": net_io.bytes_sent / (1024 * 1024),  # Перевод в МБ
        "Network Received": net_io.bytes_recv / (1024 * 1024),  # Перевод в МБ
        "Uptime": f"{hours} часов {minutes} минут {seconds} секунд",  # Отображаем корректно
        **disks
    }

@app.route('/metrics')
def metrics():
    return jsonify(get_system_metrics())

@app.route('/')
def index():
    return '''
    <!DOCTYPE html>
    <html lang="ru">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Мониторинг системы</title>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        <style>
            body {
                font-family: Arial, sans-serif;
                text-align: center;
                background-color: #1e1e2f;
                color: white;
                padding: 20px;
            }
            h1 {
                color: #f8b400;
            }
            .container {
                max-width: 600px;
                margin: auto;
                background: #2a2a3a;
                padding: 20px;
                border-radius: 10px;
                box-shadow: 0px 0px 10px rgba(255, 255, 255, 0.1);
            }
            p {
                font-size: 18px;
                margin: 10px 0;
            }
            .metric {
                font-size: 20px;
                font-weight: bold;
                color: #4CAF50;
            }
        </style>
        <script>
            let lastSent = 0;
            let lastReceived = 0;

            async function fetchMetrics() {
                const response = await fetch('/metrics');
                const data = await response.json();
                document.getElementById('cpu').innerText = `Процессор: ${data.CPU}%`;
                document.getElementById('memory').innerText = `Память: ${data.Memory}%`;
                document.getElementById('swap').innerText = `SWAP: ${data.Swap}%`;
                document.getElementById('uptime').innerText = `Время работы: ${data.Uptime}`;

                // Рассчитываем нагрузку на сеть
                let sentRate = (data["Network Sent"] - lastSent); // МБ отправлено за 1 секунду
                let receivedRate = (data["Network Received"] - lastReceived); // МБ получено за 1 секунду

                document.getElementById('network').innerText = `Нагрузка на сеть: ${sentRate.toFixed(2)} MB/s отправлено, ${receivedRate.toFixed(2)} MB/s получено`;

                // Обновляем значения для следующего расчета
                lastSent = data["Network Sent"];
                lastReceived = data["Network Received"];

                let disksHtml = '';
                let diskData = [];
                let diskLabels = [];
                for (const [key, value] of Object.entries(data)) {
                    if (key.startsWith('Disk')) {
                        disksHtml += `<p class="metric">${key}: ${value}%</p>`;
                        diskLabels.push(key);
                        diskData.push(value);
                    }
                }
                document.getElementById('disks').innerHTML = disksHtml;

                updateChart(diskLabels, diskData);
            }
            setInterval(fetchMetrics, 1000);
            window.onload = fetchMetrics;

            function updateChart(labels, data) {
                if (window.diskChart) {
                    window.diskChart.data.labels = labels;
                    window.diskChart.data.datasets[0].data = data;
                    window.diskChart.update();
                } else {
                    const ctx = document.getElementById('diskChart').getContext('2d');
                    window.diskChart = new Chart(ctx, {
                        type: 'pie',
                        data: {
                            labels: labels,
                            datasets: [{
                                label: 'Занятость дисков (%)',
                                data: data,
                                backgroundColor: ['#f8b400', '#4CAF50', '#2196F3', '#FF5722', '#9C27B0'],
                            }]
                        }
                    });
                }
            }
        </script>
    </head>
    <body>
        <div class="container">
            <h1>Мониторинг системы</h1>
            <p id="cpu" class="metric">Процессор: ...%</p>
            <p id="memory" class="metric">Память: ...%</p>
            <p id="swap" class="metric">SWAP: ...%</p>
            <p id="network" class="metric">Нагрузка на сеть: ...</p>
            <p id="uptime" class="metric">Время работы: ...</p>
            <div id="disks"></div>
            <canvas id="diskChart" width="400" height="400"></canvas>
        </div>
    </body>
    </html>
    '''
    
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
EOF

# Запуск Gunicorn
echo "Запускаю Gunicorn сервер..."
gunicorn --workers 3 --bind 0.0.0.0:5000 app:app &

# Устанавливаем и настраиваем Nginx
echo "Устанавливаю Nginx..."
sudo apt-get install -y nginx

# Создаем конфигурацию Nginx для вашего приложения
echo "Создаю конфигурацию Nginx..."
cat > /etc/nginx/sites-available/your_app << 'EOF'
server {
    listen 80;
    server_name your_domain_or_IP;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Создаем символьную ссылку на конфигурацию в sites-enabled
echo "Активирую конфигурацию Nginx..."
sudo ln -s /etc/nginx/sites-available/your_app /etc/nginx/sites-enabled/

# Перезагружаем Nginx для применения настроек
echo "Перезагружаю Nginx..."
sudo systemctl restart nginx

echo "Все настроено! Ваше приложение доступно через Nginx на порту 80."
